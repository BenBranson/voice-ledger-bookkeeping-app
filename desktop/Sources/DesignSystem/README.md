# DesignSystem

Design tokens and the smallest primitives that enforce them. Full rationale:
`docs/design/DESIGN_SYSTEM.md`.

## What's here

| File | Contents |
|---|---|
| `VLColor.swift` | The Midnight Neon palette |
| `VLStatus.swift` | Accounting status vocabulary, environment + access-mode tones |
| `VLTypography.swift` | Type scale — condensed display vs. interface sans |
| `VLLayout.swift` | Spacing (8pt grid), radii, borders, elevation |
| `VLMotion.swift` | Durations and the Reduce Motion helper |
| `VLStatusPill.swift` | `VLStatusPill`, `VLEnvironmentBadge` |
| `VLCard.swift` | `VLCard`, `VLCoverageStrip` |

## Two rules this module exists to enforce

**1. Accent color ≠ status color.** `VLColor.cyan` means active/connected/
selected. It does not mean "good." Anything communicating what a check or
finding *means* goes through `VLStatus`, which always carries an icon and a
written label alongside the hue.

**2. Green is not a general success color.** `VLStatus.verified` has four
preconditions (data present, check completed, result current, no exception
found) per CLAUDE.md rule 5. There is deliberately no `.success` case to
reach for casually. A rule returning zero findings is not enough — that's
`.notChecked` or a `VLCoverageGap`.

## Scope

This target has **no dependency on `Core`**, on purpose. `Core` is
platform-agnostic and cannot import SwiftUI. Mapping domain types
(`Severity`, `Coverage`, `FindingStatus`) onto `VLStatus` happens in the UI
layer once those domain types are implemented — not here.

## What is NOT here yet

The application shell, navigation, workflow pages, `FindingCard`, and the
rest of the component inventory in `docs/design/UI_ARCHITECTURE.md`. Those
are Phase 1 step 1.3+, which is gated behind step 1.2's exit criteria and
has not been approved.
