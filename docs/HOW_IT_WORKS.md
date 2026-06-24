# How it works

## The comma problem

Quick promotes the full `describe`/`context`/`it` text to the XCTest selector
name by joining each nesting level with `", "`. That's fine until the prose
itself contains a comma -- `it("computes tomorrow as Sunday (0), wrapping the
week")` -- at which point a naive split on `", "` can't tell a nesting
boundary from a comma in someone's sentence.

`xctidy` resolves this by cross-referencing the literal
`describe(...)`/`context(...)`/`it(...)` string literals in the `Tests/*.swift`
files passed on the command line. If there's exactly one way to decompose a
flattened name into a `", "`-joined sequence of those known strings, it uses
that. If there's more than one way (or zero, e.g. when no spec directory was
given), it falls back to a heuristic that only splits at top-level commas
(paren-depth 0), which correctly leaves parenthetical asides like `(San
Francisco to San Jose Diridon)` intact.

## Failure folding

Because `xctidy` reads the raw `error:` line directly -- rather than text some
other formatter already reshuffled -- it can cleanly separate a failing
test's full name from its failure message and `file:line`, and fold that
into a `Failures:` section at the end, the way RSpec does. That's not
possible once something else has already joined the name and the reason with
the same `", "` separator the name itself uses internally.

## Build-phase noise

Raw `xcodebuild test` output includes the entire build log -- compiles,
links, codesign -- on top of the test results. `xctidy` suppresses all of
that by default, since it's scoped to test output specifically. The one
exception: any line containing `error:` (or a fatal/build-failed marker) is
always passed through verbatim, so a real build failure is never silently
hidden just because it didn't match a known test-line pattern.

## Output styles

Three named styles: the default (no flag), `-fd` (or `--format
documentation`), and `-fs` (or `--format spec`). All three share the same
nested tree, the same `Failures:` folding, and the exact same closing
xcbeautify-style `Test Succeeded`/`Tests Passed: ...` footer, byte-for-byte
-- only a leaf's glyph/color/text changes between styles. `-fd` and `-fs`
don't additionally print RSpec's/Mocha's own native run summary on top of
that shared footer; an earlier version of this tool did stack that native
summary before the xcbeautify footer, but seeing the three styles' real
output side by side made the run-ending look like three different
conventions for the same information, which defeated the point of having
one shared footer in the first place.

With the default (no flag), every leaf gets a glyph -- `✔` passed, `⊘` skipped,
`✖` failed. A failed leaf also keeps `(FAILED - N)`, the cross-reference
into the `Failures:` section --  the name uses internally (see
"Failure folding" above). The run ends with real xcbeautify's own
run-results footer: a green `Test Succeeded` (or red `Test Failed`)
headline, then `Tests Passed: X failed, Y skipped, Z total (N seconds)` --
that line lists all three counts despite its name, matching genuine
xcbeautify output verbatim.

```
✔ is not a transfer, since both endpoints are South County (0.0021 seconds)
✖ is not a transfer (FAILED - 1) (0.0019 seconds)
⊘ returns nil (0.0001 seconds)

Test Failed
Tests Passed: 1 failed, 1 skipped, 3 total (0.0074 seconds)
```

`-fd` clones real RSpec's `-fd`/documentation formatter's leaf rendering,
not just a lookalike: a plain colored name, no glyph, no per-test time.
Pending examples are yellow and say `(PENDING)` (RSpec's own wording,
instead of Xcode's "SKIPPED"). It does not additionally print RSpec's own
`Finished in N seconds` / `X examples, Y failures[, Z pending]` summary --
the run ends with the same xcbeautify-style `Test Succeeded`/
`Tests Passed: ...` footer every style ends with (see "Output styles"
above). Reach for this if you want RSpec's `-fd` look for the test tree
itself, with xcbeautify's verdict line at the end.

```
is not a transfer, since both endpoints are South County
is not a transfer (FAILED - 1)
returns nil (PENDING)

Test Failed
Tests Passed: 1 failed, 1 skipped, 3 total (0.026 seconds)
```

`-fs` clones the more common convention used by reporters like Mocha's
default `spec` reporter or Jest, again for leaf rendering only: a green `✔`
with the passing test's name dimmed to gray (de-emphasized, since passes
aren't where attention is needed), a red `✗ name (FAILED - N)` for
failures, and a cyan `- name (SKIPPED)` for skips. It does not additionally
print Mocha's own `N passing (Ttime s)` / `M failing` / `K pending` summary
-- the run ends with the same xcbeautify-style `Test Succeeded`/
`Tests Passed: ...` footer every style ends with.

```
✔ is not a transfer, since both endpoints are South County
✗ is not a transfer (FAILED - 1)
- returns nil (SKIPPED)

Test Failed
Tests Passed: 1 failed, 1 skipped, 5 total (18031.0 seconds)
```

## Where this fits in a fastlane pipeline

`xctidy` is a *formatter*, not a post-processor: it parses `xcodebuild`'s raw
output directly, the same input xcbeautify and xcpretty parse. That means it
occupies the same pipeline slot fastlane already hands to xcbeautify/xcpretty
via `scan`'s (and `gym`'s/`snapshot`'s) [`xcodebuild_formatter`
option](https://docs.fastlane.tools/best-practices/xcodebuild-formatters/) --
swap the value, don't add a stage after it:

```ruby
# Fastfile
lane :test do
  scan(
    scheme: "MyApp",
    xcodebuild_formatter: "/usr/local/bin/xctidy -fd Tests"
  )
end
```

No xcbeautify or xcpretty install required -- `xctidy` reads `xcodebuild`'s
output on its own. Swap `-fd` for `-fs`, or drop the flag entirely for the
default, to change styles; the trailing `Tests` is the positional path to
your specs directory, used for the comma-disambiguation described above.

## Known limitations

**Quick/Nimble-on-XCTest only.** `xctidy` is scoped to suites built on
Quick/Nimble's `describe`/`context`/`it`, which XCTest sees as one
comma-flattened selector name (see "The comma problem" above). It doesn't
apply the same way to Swift Testing's native macro syntax (`@Test`,
`@Suite`) -- that's a different output shape entirely, not just a different
flag.

**Parallel testing isn't handled yet.** The tree-rendering dedup (collapsing
a shared `describe`/`context` prefix between adjacent leaves -- see
`renderCase` in `Engine.swift`) keeps a single global "last path." Under
`xcodebuild`'s `-parallel-testing-enabled`, test-case lines from different
destinations can interleave, which would corrupt that dedup. The fix is
likely straightforward -- per-destination dedup state instead of one global
one -- but nothing in `Engine.swift` does this yet, and there's no test
covering parallel output. Worth fixing before relying on `xctidy` for a
parallelized test plan.

## Background

This engine started as a Python post-processor
([`test_formatter.py`](https://github.com/woodie/next-caltrain-swift)) that
cleaned up [xcbeautify](https://github.com/cpisciotta/xcbeautify)'s already-
reformatted output. That worked, but had two limits: it depended on
xcbeautify being installed and run first, and by the time text reached it,
xcbeautify had already joined a failing test's name and failure reason with
the same separator, making it impossible to fold failures into the tree.
`xctidy` is a from-scratch Swift implementation that reads xcodebuild's raw
output directly instead, removing that dependency and adding the failure
folding the Python version couldn't do.

It's not the first time this exact problem has come up: a near-identical
comma-disambiguation approach was built for Go's Ginkgo as
[ginkgo-fd](https://github.com/woodie/ginkgo-fd), with a related fix
([onsi/ginkgo#1670](https://github.com/onsi/ginkgo/pull/1670)) merged
upstream into Ginkgo itself.

`xctidy` started as a proof-of-concept exploring whether
[xcbeautify](https://github.com/cpisciotta/xcbeautify) could support this as
a built-in renderer mode rather than a separate tool: xcbeautify's `Parser`
already recognizes every line this needs (`TestSuiteStartedCaptureGroup`,
`TestCaseStartedCaptureGroup`, `TestCasePassedCaptureGroup`,
`FailingTestCaptureGroup`, and so on), and it already ships alternate
renderers (`--renderer github-actions`/`teamcity`/`azure-devops-pipelines`),
so a documentation-style mode looked like it could plausibly reuse that same
extension point instead of needing new parsing. That pitch was never filed
upstream, but it's the reason `xctidy` reads `xcodebuild`'s raw output
directly rather than post-processing some other tool's text -- the same
property that makes failure-folding possible (see "Failure folding" above).
`xctidy` has since grown into its own standalone formatter, with its own
name and its own drop-in story for a fastlane pipeline (see above).
