// Pulled out of main.swift so the --version/-v detection is unit-testable
// like the rest of the argument-handling surface in XctidyKit -- main.swift
// itself is an executableTarget's top-level script code, which isn't
// reachable from XctidyKitTests. See VersionFlagSpec.

/// Whether `args` requests version reporting. Checked by main.swift before
/// the stdin-reading loop starts -- it must short-circuit immediately rather
/// than fall through to `readLine()`, which would otherwise hang waiting for
/// piped input that will never arrive when someone just runs `xctidy
/// --version` directly.
public func wantsVersion(_ args: [String]) -> Bool {
    args.contains("--version") || args.contains("-v")
}
