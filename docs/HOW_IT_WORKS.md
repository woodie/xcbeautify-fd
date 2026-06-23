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

Three named styles, picked with `--classic`/`--fd`/`--spec` (or `--style
<name>`). All three share the same nested tree and the same `Failures:`
folding -- only a leaf's glyph/color/text and the run-level summary change.

`--classic` (default) matches what the original
[`test_formatter.py`](https://github.com/woodie/next-caltrain-swift) actually
produced: every leaf gets a glyph -- `✔` passed, `⊘` skipped, `✖` failed --
plus the per-test `(N seconds)` `xcodebuild` itself reports, both colored
(green/cyan/red). A failed leaf also keeps `(FAILED - N)`, the cross-reference
into the `Failures:` section -- an improvement the original couldn't make,
since by the time text reached it, xcbeautify had already joined a failing
test's name and reason with the same separator the name uses internally (see
"Failure folding" above). No run summary at the end, matching the original.

```
✔ is not a transfer, since both endpoints are South County (0.0021 seconds)
✖ is not a transfer (FAILED - 1) (0.0019 seconds)
⊘ returns nil (0.0001 seconds)
```

`--fd` is an actual clone of real RSpec's `-fd`/documentation formatter, not
just a lookalike: a plain colored name, no glyph, no per-test time. Pending
examples are yellow and say `(PENDING)` (RSpec's own wording, instead of
Xcode's "SKIPPED"), and the run ends with RSpec's own summary footer --
`Finished in N seconds` followed by `X examples, Y failures[, Z pending]`.
Reach for this if you want output indistinguishable from a real `rspec -fd`
run.

```
is not a transfer, since both endpoints are South County
is not a transfer (FAILED - 1)
returns nil (PENDING)

Finished in 0.026 seconds
3 examples, 1 failure, 1 pending
```

`--spec` is the more common convention used by reporters like Mocha's
default `spec` reporter or Jest: a green `✔` with the passing test's name
dimmed to gray (de-emphasized, since passes aren't where attention is
needed), a red `✗ name (FAILED - N)` for failures, and a cyan
`- name (SKIPPED)` for skips. The run ends with Mocha's own summary lines --
`N passing (Ttime s)`, then `M failing`/`K pending` only when nonzero (the
"s" suffix because `xcodebuild` reports the total run time in seconds, not
Mocha's milliseconds).

```
✔ is not a transfer, since both endpoints are South County
✗ is not a transfer (FAILED - 1)
- returns nil (SKIPPED)

3 passing (18031.0s)
1 failing
1 pending
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
    xcodebuild_formatter: "/usr/local/bin/xctidy --fd Tests"
  )
end
```

No xcbeautify or xcpretty install required -- `xctidy` reads `xcodebuild`'s
output on its own. Swap `--fd` for `--classic` (the default if the flag is
omitted entirely) or `--spec` to change styles; the trailing `Tests` is the
positional path to your specs directory, used for the comma-disambiguation
described above.

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

It started as a proof-of-concept exploring whether xcbeautify could support
this as a built-in mode -- that pitch still exists as a draft proposal -- but
it has since grown into its own standalone formatter, with its own name and
its own drop-in story for a fastlane pipeline (see above).
