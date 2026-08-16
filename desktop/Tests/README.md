# Running tests

These targets are written against **Swift Testing** (`import Testing`,
`@Test`, `#expect`), which is Apple's current recommended framework and what
`docs/phase-0/12_TEST_STRATEGY.md` §12.5 illustrates.

## A known gap, stated plainly

This repo was scaffolded in an environment with only the Command Line Tools
installed (`xcode-select -p` → `/Library/Developer/CommandLineTools`), not
full Xcode.app. In that environment, **neither `Testing` nor `XCTest`
resolve** — both ship as part of Xcode's bundled toolchain, not the
standalone Command Line Tools.

I tried pulling `swift-testing` in as an explicit SPM package dependency to
work around this. It resolves and compiles, but linking fails:

```
ld: library '_TestingInterop' not found
```

`_TestingInterop` is itself a binary shipped inside Xcode's toolchain, not
something buildable from `swift-testing`'s own sources — so this workaround
doesn't actually close the gap, it just moves where it shows up. I reverted
it rather than leave an unpinned `branch: "main"` dependency with a large
build footprint (swift-syntax, swift-argument-parser) sitting in the repo for
a fix that doesn't work.

**What this means concretely:**
- `swift build` — verified clean in this environment. All production code
  (`Core`, `IntegrationsQuickBooks`, the stub targets, `voiceledger-devtool`)
  compiles.
- `swift test` — **not verified here.** The test files were written
  carefully and reviewed by hand, but I cannot claim they compile or pass,
  because I have no way to compile them in this environment.

**Run `swift test` yourself once Xcode is installed** (needed anyway for
SwiftUI work later in the Build Order) and treat the first run as the actual
verification of everything under `Tests/`. If something doesn't compile,
that's real signal — fix it then, don't assume it was fine because it "looked
right."
