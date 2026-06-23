# Working with xctidy

`xctidy` is a standalone Swift CLI that parses raw `xcodebuild
test`/`swift test` output directly -- the same textual protocol xcpretty and
xcbeautify both regex-match -- into a nested `describe`/`context`/`it` tree,
rendered in any of three named conventions (`--classic`/`--fd`/`--spec`; see
`docs/HOW_IT_WORKS.md`, "Output styles"). It started as a proof-of-concept
built ahead of proposing the same raw-output approach as a built-in mode for
upstream [`cpisciotta/xcbeautify`](https://github.com/cpisciotta/xcbeautify)
(draft proposal at `../xcbeautify-fd-PROPOSAL.md`, one level up, outside this
repo so it isn't committed here) -- but it's since grown into its own
standalone formatter with its own name and its own fastlane drop-in-
replacement story.

The engine itself is a Swift port of `tools/test_formatter.py` from the
`next-caltrain-swift` sibling repo (see that repo's `docs/COWORK.md`, "Test
output formatting"), reworked to read xcodebuild's raw output instead of
post-processing xcbeautify's already-flattened text. Reading the raw protocol
directly is what makes failure-folding possible here (see
`docs/HOW_IT_WORKS.md`, "Failure folding") -- the Python version couldn't do
that because by the time text reached it, xcbeautify had already joined a
failing test's name and failure reason with the same `", "` separator the
name itself uses internally.

## Naming history

The repo/package started life as `xcbeautify-fd` (an `-fd`-suffix nod to
RSpec's `-fd` flag). That undersold it once `--classic`/`--spec` existed
alongside `--fd` -- it read as "just an -fd clone." Renamed to `xcpolish`
first, then -- the user's final call, made by browsing a thesaurus entry for
"tidy" rather than picking from xc-prefixed candidates -- to **`xctidy`**,
which is the name everywhere now: package, executable, library target
(`XctidyKit`), directory names, and all docs.

## Edit cycle

Cowork has no Swift toolchain in its sandbox, so `swift build`/`swift test`
can't be run or verified here. Cowork edits `Sources/`/`Tests/` directly with
its file tools, reasons about expected behavior, and hands back exact
verification commands for the user to run on their own Mac. Treat any change
as unverified until the user confirms a real build/test run.

The sandbox also can't unlink (`rm`/`rmdir`) files inside the mounted
workspace folder (a virtiofs restriction) -- but a same-filesystem `mv`
*does* work, including renaming a directory in place (confirmed by the
`Sources/XcbeautifyFDKit` → `Sources/XcpolishKit` → `Sources/XctidyKit`-style
renames done across this arc). When a file needs deleting rather than
renaming, Cowork blanks its *content* to a short comment explaining why and
pointing at the exact `git rm`/`rm`/`rmdir` command for the user to run
themselves. `Tests/XctidyKitTests/EngineTests.swift` and
`Sources/xctidy/main_copy2.swift` are in exactly that state right now (see
"Where we left off" below for the full cleanup list).

Nothing in this arc (the Quick/Nimble conversion, the render-style split, the
rename) has been committed yet -- see `git status` below. Following the
sibling repos' convention: hold off committing until the user has actually
run the build and tests on their Mac and confirmed it works.

## Architecture

- `Sources/XctidyKit/Engine.swift` -- the core engine. `Matchers` mirrors
  xcpretty's `parser.rb` regexes (one deliberate improvement: the
  suite/class capture uses `\S+` instead of xcpretty's ambiguous `(.*) (.*)`,
  since class names never contain spaces). `loadKnownAtoms`/`splitPath`
  implement the same dictionary-based comma-disambiguation as the Python
  tool's `load_known_atoms()`/`split_path()`. `Engine` is the stateful
  line-by-line renderer; `RenderStyle` controls which of the three output
  styles it produces.
- `Sources/xctidy/main.swift` -- CLI entry point. Reads stdin line by line,
  feeds `Engine`, prints `engine.finish()`. Flags: `--classic` (default),
  `--fd`, `--spec`, or `--style <name>`. Positional arg is the specs
  directory passed to `loadKnownAtoms`.
- `docs/HOW_IT_WORKS.md` -- the comma problem, failure folding, build-noise
  suppression, a full description of the three output styles, and where
  `xctidy` fits in a fastlane pipeline (`xcodebuild_formatter`). Read that
  before touching `RenderStyle` or `renderCase`/`finish()` in `Engine.swift`.

### Render styles

`.classic` (default) is the original Python tool's look: glyph (`✔`/`⊘`/`✖`)
plus the per-test `(N seconds)` xcodebuild reports, no summary footer. `.fd`
is a faithful clone of real RSpec's `-fd` formatter: no glyph, yellow
`(PENDING)` instead of `(SKIPPED)`, plus RSpec's own `Finished in N seconds` /
`X examples, Y failures[, Z pending]` footer. `.spec` is the Mocha/Jest
`✔`-green/gray-name convention, ending in Mocha's own `N passing (Ttime s)` /
`M failing` / `K pending` footer. Full detail in `docs/HOW_IT_WORKS.md`'s
"Output styles" section -- don't duplicate it here, that doc is the source of
truth.

## Tests

Quick/Nimble (added as test-only dependencies in `Package.swift`) so the
suite can dogfood the tool's own headline feature -- a real, genuinely
comma-flattened Quick test name to disambiguate, not just a hand-built
fixture string.

- `Tests/XctidyKitTests/EngineSpec.swift` -- the main spec, a single
  `final class EngineSpec: QuickSpec` with `override class func spec()`
  (Quick 7.x uses a *class* method here, not an instance method --
  `override func spec()` fails to compile with "method does not override any
  method from its superclass"). Nested `describe`/`context`/`it` covering
  `loadKnownAtoms`, `splitPath` (both the dictionary-disambiguation path and
  the heuristic fallback), and `Engine` (tree rendering, noise suppression,
  color output, and all three render styles' leaf/footer behavior).
- `Tests/XctidyKitTests/AnsiColorDemoSpec.swift` -- a small, *real* Quick
  spec (not just fixtures) proving the comma-disambiguation logic against
  genuine Quick-generated output, including a deliberately tricky
  bare-prose-comma case (no parens at all) that only the atom-dictionary
  approach resolves correctly -- the paren-depth heuristic alone would
  over-split it.
- `Tests/XctidyKitTests/EngineTests.swift` -- superseded. Used to be a flat
  `XCTestCase` with the same cases now in `EngineSpec.swift`; blanked to a
  placeholder comment (sandbox can't delete it -- see "Edit cycle" above).
  **Still needs `git rm Tests/XctidyKitTests/EngineTests.swift` from the
  user.**

## Where we left off (2026-06-23)

Most recent work, in order: (1) split the old two-way `--fd`/`--spec` flag
into the three-way `--classic`/`--fd`/`--spec` style now documented above,
making `--classic` the default and byte-for-byte what the original Python
tool produced; (2) reworked `--classic` to match a `swift.txt` reference
sample exactly (glyph + per-leaf elapsed time, which an earlier pass had
dropped); (3) added a Mocha-style `N passing (Ttime s)` summary footer to
`--spec`, matching a `kotlin.txt` reference sample; (4) renamed the project
twice -- `xcbeautify-fd` → `xcpolish` (interim) → **`xctidy`** (the user's
final answer, picked by browsing a thesaurus entry for "tidy" rather than
from the xc-prefixed shortlist) -- across `Package.swift`, `Sources/`,
`Tests/`, and all source comments; (5) rewrote `README.md`,
`docs/HOW_IT_WORKS.md`, and this file to reflect the new name, the three
styles' real current behavior, and `xctidy`'s positioning as a fastlane
drop-in *replacement* formatter (same `xcodebuild_formatter` pipeline slot as
xcbeautify/xcpretty, not a post-processor chained after either) -- including
a concrete `Fastfile` `scan(xcodebuild_formatter: ...)` snippet, verified
against fastlane's own docs.

Status as of this doc:

- `Engine.swift`, `main.swift`, `EngineSpec.swift`, and `AnsiColorDemoSpec.swift`
  are all consistent with each other under the `xctidy` name and the 3-way
  style split.
- `README.md` and `docs/HOW_IT_WORKS.md` describe all three styles accurately
  and document the fastlane integration.
- `../xcbeautify-fd-PROPOSAL.md` (outside this repo) was checked earlier in
  this arc and doesn't mention `--fd`/`--spec`/output styles at all, so it
  didn't need updating for the style work -- it also predates the rename to
  `xctidy` and hasn't been revisited for that, since it lives outside this
  repo and outside Cowork's reach.
- **Not yet done**: no `swift build`/`swift test` has been run against any of
  this -- there's no Swift toolchain in the sandbox. Next step for whoever
  picks this up is to run, on a real Mac, from the repo root:

  ```
  swift build -c release
  swift test 2>&1 | .build/release/xctidy Tests/XctidyKitTests --classic
  swift test 2>&1 | .build/release/xctidy Tests/XctidyKitTests --fd
  swift test 2>&1 | .build/release/xctidy Tests/XctidyKitTests --spec
  ```

  `--classic` should show a glyph + `(N seconds)` per leaf; `--fd` should
  show yellow `(PENDING)` and end with a `Finished in...`/`N examples...`
  footer; `--spec` should show green `✔`/gray names and end with `N passing
  (Ttime s)`.
- Cleanup the user still needs to run themselves (sandbox can't delete
  files -- see "Edit cycle" above):

  ```
  git rm Tests/XctidyKitTests/EngineTests.swift
  git rm Sources/xctidy/main_copy2.swift
  rm Sources/xctidy/_scratch_test.txt
  rmdir Sources/TestDirRename2
  ```

- `git status` at the time of writing: everything from the Quick/Nimble
  conversion onward -- the render-style split, both renames, and this docs
  pass -- is sitting in the working tree, unpushed and uncommitted. Repo
  history is still just two commits (`d8c27e5` initial scaffold, `ecf5d6d`
  the first Swift Package implementation). Per the sibling repos'
  convention: hold off committing until the user has run the build/tests
  above and confirmed it works.
