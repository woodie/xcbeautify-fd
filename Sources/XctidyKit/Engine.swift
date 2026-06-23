import Foundation

/// xctidy's core engine.
///
/// Parses RAW `xcodebuild test` output directly -- the same textual protocol
/// xcpretty's `parser.rb` and xcbeautify both regex-match (there is no formal
/// API; this *is* the API). No dependency on xcbeautify or xcpretty being
/// installed.
///
/// Quick promotes the full comma-joined `describe`/`context`/`it` text
/// (literal prose, commas and all) to be the XCTest selector name, so a raw
/// `Test Case '-[Class full, prose, name]'` line can't be split on every
/// comma -- some commas are nesting separators, some are just commas in the
/// prose. This engine disambiguates by cross-referencing the literal
/// `describe(...)`/`context(...)`/`it(...)` strings found in the project's
/// `Tests/*.swift` files (see `loadKnownAtoms`), falling back to a
/// paren-depth-aware heuristic split when that dictionary can't resolve the
/// name uniquely.

// MARK: - Raw xcodebuild line matchers
//
// Mirrors xcpretty's parser.rb matchers. One deliberate improvement: the
// suite/class capture group uses `\S+` (no whitespace) instead of xcpretty's
// ambiguous `(.*) (.*)`, since Swift/Obj-C class names never contain spaces.
// That cleanly separates "ClassName" from "full prose comma-joined name" --
// xcpretty's own pattern just greedily grabs everything as a flat string,
// which is fine for its flat failure list but unusable for a nested tree.

enum Matchers {
    static let suiteStarted = try! NSRegularExpression(
        pattern: #"^Test Suite '(.+)' started at (.+)\.$"#)
    static let suiteFinished = try! NSRegularExpression(
        pattern: #"^Test Suite '(.+)' (passed|failed) at (.+)\.$"#)
    static let caseStarted = try! NSRegularExpression(
        pattern: #"^Test Case '-\[(\S+) (.+)\]' started\.$"#)
    static let caseFinished = try! NSRegularExpression(
        pattern: #"^Test Case '-\[(\S+) (.+)\]' (passed|failed|skipped) \(([\d.]+) seconds\)\.$"#)
    static let failureDetail = try! NSRegularExpression(
        pattern: #"^(.+:\d+): error: [+-]\[(\S+) (.+)\] : (.*)$"#)
    static let executedSummary = try! NSRegularExpression(
        pattern: #"^\s*Executed \d+ tests?, with \d+ failures? \(\d+ unexpected\) in ([\d.]+) \([\d.]+\) seconds$"#)
    static let atomCall = try! NSRegularExpression(
        pattern: #"\b(?:describe|context|it)\(\s*"((?:[^"\\]|\\.)*)""#)
}

extension NSRegularExpression {
    func firstMatch(in s: String) -> NSTextCheckingResult? {
        firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
}

extension NSTextCheckingResult {
    func group(_ idx: Int, in original: String) -> String? {
        guard idx < numberOfRanges else { return nil }
        let r = range(at: idx)
        guard r.location != NSNotFound else { return nil }
        return (original as NSString).substring(with: r)
    }
}

// MARK: - Dictionary-based comma disambiguation
//
// Ported from next-caltrain-swift's tools/test_formatter.py. Builds a set of
// every known describe/context/it literal string by scanning the project's
// spec files, then tries to decompose a flattened Quick name into a
// `", "`-joined sequence of those known atoms. We only need to know whether
// there is exactly one way to do that (unambiguous) or not (fall back to a
// heuristic), so the search stops after finding 2 decompositions.

public func unescapeSwiftLiteral(_ raw: String) -> String {
    var out = ""
    let chars = Array(raw)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if ch == "\\", i + 1 < chars.count {
            switch chars[i + 1] {
            case "n": out.append("\n")
            case "t": out.append("\t")
            default: out.append(chars[i + 1])
            }
            i += 2
        } else {
            out.append(ch)
            i += 1
        }
    }
    return out
}

/// Scans `*.swift` files directly inside `specsDir` (non-recursive, matching
/// the original Python tool's `Path(specs_dir).glob("*.swift")`) for
/// `describe("...")` / `context("...")` / `it("...")` string literals.
public func loadKnownAtoms(specsDir: String) -> Set<String> {
    var atoms = Set<String>()
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: specsDir) else {
        return atoms
    }
    for file in entries.filter({ $0.hasSuffix(".swift") }).sorted() {
        let path = (specsDir as NSString).appendingPathComponent(file)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        for m in Matchers.atomCall.matches(in: text, range: range) {
            let raw = nsText.substring(with: m.range(at: 1))
            atoms.insert(unescapeSwiftLiteral(raw))
        }
    }
    return atoms
}

func findDecompositions(_ name: String, atoms: Set<String>, limit: Int = 2) -> [[String]] {
    if atoms.isEmpty { return [] }
    let byLen = atoms.sorted { $0.count > $1.count }
    let chars = Array(name)
    let n = chars.count
    var results: [[String]] = []

    func rec(_ start: Int, _ path: inout [String]) {
        if results.count >= limit { return }
        if start == n {
            results.append(path)
            return
        }
        for atom in byLen {
            if results.count >= limit { return }
            if atom.isEmpty { continue }
            let atomChars = Array(atom)
            let end = start + atomChars.count
            if end > n { continue }
            if Array(chars[start..<end]) != atomChars { continue }
            if end == n {
                path.append(atom)
                rec(end, &path)
                path.removeLast()
            } else if end + 2 <= n, chars[end] == ",", chars[end + 1] == " " {
                path.append(atom)
                rec(end + 2, &path)
                path.removeLast()
            }
        }
    }

    var path: [String] = []
    rec(0, &path)
    return results
}

/// Splits only at top-level (paren-depth 0) `", "` -- used when the
/// dictionary is empty or can't disambiguate. Keeps parenthetical asides
/// like "(San Francisco to San Jose Diridon)" intact.
func splitHeuristic(_ name: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var depth = 0
    let chars = Array(name)
    var i = 0
    let n = chars.count
    while i < n {
        let ch = chars[i]
        if ch == "(" {
            depth += 1
            current.append(ch)
            i += 1
        } else if ch == ")" {
            depth = max(depth - 1, 0)
            current.append(ch)
            i += 1
        } else if depth == 0, i + 1 < n, chars[i] == ",", chars[i + 1] == " " {
            parts.append(current)
            current = ""
            i += 2
        } else {
            current.append(ch)
            i += 1
        }
    }
    parts.append(current)
    return parts
}

public func splitPath(_ name: String, atoms: Set<String>) -> [String] {
    let decompositions = findDecompositions(name, atoms: atoms)
    if decompositions.count == 1 {
        return decompositions[0]
    }
    return splitHeuristic(name)
}

// MARK: - Color output

enum AnsiColor: String {
    case red = "31"
    case green = "32"
    case yellow = "33"
    case cyan = "36"
    case gray = "90"
}

/// `.classic` (default) faithfully reproduces what `tools/test_formatter.py`
/// actually looked like in practice: every leaf gets xcbeautify's own
/// "✔"/"⊘"/"✖" glyph plus the per-test "(N seconds)" xcodebuild reports,
/// both colored (green/cyan/red); a failed leaf also keeps this project's
/// "(FAILED - N)" cross-reference into the Failures section -- an
/// improvement the original couldn't make (see docs/HOW_IT_WORKS.md,
/// "Failure folding"). No run summary at the end, matching the original.
///
/// `.fd` is an actual clone of real RSpec's `-fd`/documentation formatter:
/// a plain colored name with no glyph and no per-test time (this is the
/// glyph-less tree `.classic` rendered before the swift.txt-fidelity
/// rework), pending examples are yellow and say "(PENDING)" (RSpec's
/// wording, not Xcode's "SKIPPED"), and the run ends with RSpec's own
/// "Finished in N seconds" + "X examples, Y failures[, Z pending]" footer.
///
/// `.spec` is the more common convention used by reporters like Mocha's
/// default `spec` reporter or Jest: a green "✔" with the passing test's name
/// dimmed to gray (de-emphasized, since passes aren't where attention is
/// needed), a red "✗ name (FAILED - N)" for failures, and a cyan
/// "- name (SKIPPED)" for skips -- plus, at the end, Mocha's own
/// "N passing (Ttime s)" / "M failing" / "K pending" summary lines.
public enum RenderStyle: Equatable {
    case classic
    case fd
    case spec
}

// MARK: - Failures

public struct EngineFailure {
    public let n: Int
    public let full: [String]
    public let message: String
    public let location: String
}

// MARK: - Engine

public final class Engine {
    private let atoms: Set<String>
    private let tty: Bool
    private let style: RenderStyle
    private var lastPath: [String] = []
    private var curFailureLines: [(location: String, reason: String)] = []
    private(set) public var failures: [EngineFailure] = []
    private var out: [String] = []
    private var exampleCount = 0
    private var passedCount = 0
    private var pendingCount = 0
    private var lastTestTimeText: String?

    public init(atoms: Set<String>, tty: Bool, style: RenderStyle = .classic) {
        self.atoms = atoms
        self.tty = tty
        self.style = style
    }

    private func colorize(_ color: AnsiColor, _ s: String) -> String {
        guard tty else { return s }
        return "\u{1B}[\(color.rawValue)m\(s)\u{1B}[0m"
    }

    private func emit(_ s: String = "") {
        out.append(s)
    }

    /// Feed one line of raw `xcodebuild test` output. Lines that are part of
    /// the test protocol are consumed and re-rendered as the nested tree;
    /// everything else (compiles, links, codesign -- the build-phase noise
    /// xcpretty/xcbeautify spend most of their matchers on) is suppressed,
    /// *except* for anything containing "error:" or a fatal/build-failed
    /// marker, which is passed through verbatim so a real build failure is
    /// never silently hidden. This tool is scoped to test output, the same
    /// way ginkgo-fd doesn't bother reformatting `go build`'s own output.
    public func feedLine(_ line: String) {
        if let m = Matchers.suiteStarted.firstMatch(in: line), let name = m.group(1, in: line) {
            emit()
            emit(name)
            return
        }
        if Matchers.suiteFinished.firstMatch(in: line) != nil {
            return
        }
        if let m = Matchers.failureDetail.firstMatch(in: line),
            let location = m.group(1, in: line), let reason = m.group(4, in: line)
        {
            curFailureLines.append((location: location, reason: reason))
            return
        }
        if let m = Matchers.caseFinished.firstMatch(in: line),
            let name = m.group(2, in: line), let state = m.group(3, in: line)
        {
            let path = splitPath(name, atoms: atoms)
            // group(4) is the per-test "(N seconds)" xcodebuild reports for
            // every case regardless of outcome -- .classic surfaces it
            // directly (see RenderStyle doc comment); .fd/.spec don't use it
            // per-leaf, only lastTestTimeText's run-level total.
            let time = m.group(4, in: line)
            renderCase(path: path, state: state, time: time)
            curFailureLines = []
            return
        }
        if Matchers.caseStarted.firstMatch(in: line) != nil {
            return  // pure bookkeeping; the tree is rendered from caseFinished
        }
        if let m = Matchers.executedSummary.firstMatch(in: line) {
            // Suppressed from passthrough either way; under --fd we keep the
            // captured time and render our own RSpec-style footer in
            // finish() instead. There's one of these per nesting level
            // (per-class, per-bundle, "All tests"); the last one wins, which
            // is always the outermost/final total since XCTest finishes
            // inner scopes before outer ones.
            lastTestTimeText = m.group(1, in: line)
            return
        }
        if line.contains("error:") || line.contains("fatal error:")
            || line.contains("** BUILD FAILED **") || line.contains("** TEST FAILED **")
        {
            emit(line)
            return
        }
        // else: suppress routine build-phase noise.
    }

    private func renderCase(path: [String], state: String, time: String?) {
        exampleCount += 1
        var shared = 0
        for (a, b) in zip(path, lastPath) {
            if a != b { break }
            shared += 1
        }
        if path.count > 1 {
            for depth in shared..<(path.count - 1) {
                emit(String(repeating: "  ", count: depth + 1) + path[depth])
            }
        }
        let leafDepth = path.count - 1
        let name = path[path.count - 1]
        var label = name

        // .classic's "(N seconds)" suffix, colored to match its glyph --
        // mirrors xcbeautify's own .coloredTime(), which test_formatter.py
        // re-emitted verbatim (see that script's TIMED_RE/module docstring).
        func timedSuffix(_ color: AnsiColor) -> String {
            guard let time else { return "" }
            return " (\(colorize(color, time)) seconds)"
        }

        switch state {
        case "passed":
            passedCount += 1
            switch style {
            case .classic:
                label = "\(colorize(.green, "✔")) \(name)\(timedSuffix(.green))"
            case .fd:
                label = colorize(.green, name)
            case .spec:
                label = colorize(.green, "✔") + " " + colorize(.gray, name)
            }
        case "skipped":
            pendingCount += 1
            switch style {
            case .classic:
                // No "(SKIPPED)" text suffix here, deliberately -- the
                // original test_formatter.py distinguished skips from
                // passes by glyph (⊘ vs ✔) and color alone. --fd and
                // --spec both spell it out in words; reach for those if
                // a glyph-only signal isn't enough in your terminal/font.
                label = "\(colorize(.cyan, "⊘")) \(name)\(timedSuffix(.cyan))"
            case .fd:
                label = colorize(.yellow, "\(name) (PENDING)")
            case .spec:
                label = colorize(.cyan, "- \(name) (SKIPPED)")
            }
        case "failed":
            let n = failures.count + 1
            let message = curFailureLines.map { $0.reason }.joined(separator: "\n")
            let location = curFailureLines.first?.location ?? "?"
            failures.append(
                EngineFailure(
                    n: n,
                    full: path,
                    message: message.isEmpty ? "(no failure detail captured)" : message,
                    location: location))
            switch style {
            case .classic:
                // Keeps the "(FAILED - N)" Failures cross-reference (the
                // headline improvement raw-protocol parsing makes possible)
                // alongside the original's glyph + per-test time.
                label = "\(colorize(.red, "✖")) \(name) (FAILED - \(n))\(timedSuffix(.red))"
            case .fd:
                label = colorize(.red, "\(name) (FAILED - \(n))")
            case .spec:
                label = colorize(.red, "✗ \(name) (FAILED - \(n))")
            }
        default:
            break
        }

        emit(String(repeating: "  ", count: leafDepth + 1) + label)
        lastPath = path
    }

    public func finish() -> String {
        if !failures.isEmpty {
            emit()
            emit("Failures:")
            for f in failures {
                emit()
                emit("  \(f.n)) \(f.full.joined(separator: " "))")
                for line in f.message.split(separator: "\n", omittingEmptySubsequences: false) {
                    emit("     \(line)")
                }
                emit("     # \(f.location)")
            }
        }
        if style == .fd {
            emit()
            if let t = lastTestTimeText {
                emit("Finished in \(t) seconds")
            }
            var counts = pluralized(exampleCount, "example")
            counts += ", \(pluralized(failures.count, "failure"))"
            if pendingCount > 0 {
                counts += ", \(pendingCount) pending"
            }
            emit(counts)
        }
        if style == .spec {
            // Mocha's own summary lines -- "N passing (Ttime)", then
            // "M failing"/"K pending" only when nonzero, same as a real
            // Mocha `spec` reporter run. xcodebuild reports the total run
            // time in seconds (not Mocha's milliseconds), so the unit
            // suffix here is "s", e.g. kotlin.txt's "72 passing (18031.0s)".
            emit()
            var passingLine = "\(passedCount) passing"
            if let t = lastTestTimeText {
                passingLine += " (\(t)s)"
            }
            emit(colorize(.green, passingLine))
            if !failures.isEmpty {
                emit(colorize(.red, "\(failures.count) failing"))
            }
            if pendingCount > 0 {
                emit(colorize(.cyan, "\(pendingCount) pending"))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    private func pluralized(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }
}
