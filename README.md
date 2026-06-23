# xctidy

Flat `xcodebuild test` output is noisy. `xctidy` is a formatter for projects
using [Quick](https://github.com/Quick/Quick)/[Nimble](https://github.com/Quick/Nimble)
that turns it into a readable, nested `describe`/`context`/`it` tree -- in
whichever of three well-known conventions you point it at.

## 1. Install

```
git clone https://github.com/woodie/xctidy.git
cd xctidy
swift build -c release
cp .build/release/xctidy /usr/local/bin/
```

## 2. Drop it into your test pipeline

`xctidy` reads `xcodebuild`'s raw output directly -- the same textual
protocol xcbeautify and xcpretty both parse -- so it's a *replacement*
formatter, not a post-processor chained after one of them. Pipe `xcodebuild
test` straight into it, passing the path to your `Tests` directory:

```
xcodebuild test -scheme MyApp -destination "$DESTINATION" | xctidy Tests
```

Using fastlane? `scan` (and `gym`/`snapshot`) already hand this same pipeline
slot to xcbeautify/xcpretty via the `xcodebuild_formatter` option -- swap the
value, no new stage needed:

```ruby
# Fastfile
lane :test do
  scan(
    scheme: "MyApp",
    xcodebuild_formatter: "/usr/local/bin/xctidy --fd Tests"
  )
end
```

## 3. Pick a style

Three named styles, each matching a convention you've probably already seen
in some other test runner:

| Flag | Convention | Look |
|---|---|---|
| `--classic` (default) | this project's own original Python formatter | glyph + `name (N seconds)`, failures add `(FAILED - N)`, no summary footer |
| `--fd` | RSpec's `-fd`/documentation formatter | plain colored name, yellow `(PENDING)` for skips, ends with RSpec's `Finished in...`/`X examples, Y failures` footer |
| `--spec` | Mocha's default `spec` reporter / Jest | green `✔` + gray name, red `✗ name (FAILED - N)`, ends with Mocha's `N passing (Ttime)` footer |

Full output samples for all three: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md#output-styles).

## 4. Run tests

Run your test suite the same way you always have -- `xctidy` is just the
last stage of the pipe from step 2. Here's `--classic`, the default:

```
NextCaltrainTests.xctest

GoodTimesSpec
  GoodTimes
    when 'today' is fixed via debugOverrideDotw
      and today is Saturday (6)
        ✔ computes tomorrow as Sunday (0), wrapping the week (0.0033 seconds)

CaltrainServiceSpec
  CaltrainService
    #routes(from:to:scheduleType:)
      for a direct diesel trip (Morgan Hill to Gilroy)
        ✔ is not a transfer, since both endpoints are South County (0.0021 seconds)
      for a direct electric trip (San Francisco to San Jose Diridon)
        ✖ is not a transfer (FAILED - 1) (0.0019 seconds)
    #nextIndex(trips:minutes:)
      when given an empty trip list
        ⊘ returns nil (0.0001 seconds)

Failures:

  1) CaltrainService #routes(from:to:scheduleType:) for a direct electric trip (San Francisco to San Jose Diridon) is not a transfer
     XCTAssertFalse failed - expected false, got true
     # /path/to/Tests/CaltrainServiceSpec.swift:55
```

Build-phase output (compiles, links, codesign) is suppressed. Lines
containing `error:` are always passed through, so a real build failure is
never hidden.

## More

How the comma-disambiguation, failure-folding, and fastlane integration
actually work: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)
