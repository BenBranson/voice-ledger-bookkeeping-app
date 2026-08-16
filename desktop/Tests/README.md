# Running tests

These targets are written against **Swift Testing** (`import Testing`,
`@Test`, `#expect`), which is Apple's current recommended framework and what
`docs/phase-0/12_TEST_STRATEGY.md` §12.5 illustrates.

## Verified 2026-08-16 — 12/12 passing

```
swift test
...
Test run with 12 tests in 2 suites passed after 0.071 seconds.
```

4 in the `Money` suite, 4 in `Contrast — WCAG AA`, 4 ungrouped (module
boundary lint, secret scan, `BackendConfiguration` env-var validation). This
was the first actual execution of these files — see below for why it took
until now, and why "looked right on review" was never treated as equivalent
to a passing test in the meantime.

## History: why this took a second environment

This repo was originally scaffolded in an environment with only the Command
Line Tools installed (`xcode-select -p` → `/Library/Developer/CommandLineTools`),
not full Xcode.app. In that environment, **neither `Testing` nor `XCTest`
resolve** — both ship as part of Xcode's bundled toolchain, not the
standalone Command Line Tools.

An attempt to pull `swift-testing` in as an explicit SPM package dependency
to work around this resolved and compiled, but failed at link time:

```
ld: library '_TestingInterop' not found
```

`_TestingInterop` is itself a binary shipped inside Xcode's toolchain, not
something buildable from `swift-testing`'s own sources — so that workaround
didn't actually close the gap, it just moved where it showed up. It was
reverted rather than left as an unpinned `branch: "main"` dependency with a
large build footprint (swift-syntax, swift-argument-parser) sitting in the
repo for a fix that didn't work.

In that environment, only `swift build` could be verified (all production
code compiled clean); `swift test` was explicitly flagged as unverified
rather than assumed to pass. Once Xcode was installed on the actual dev
machine (confirmed via `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`),
`swift test` ran immediately with no changes needed to any test file — the
code was correct the whole time, it just hadn't been checked.

**Going forward:** run `swift test` after any change under `Sources/` or
`Tests/`. A failure here is real signal.
