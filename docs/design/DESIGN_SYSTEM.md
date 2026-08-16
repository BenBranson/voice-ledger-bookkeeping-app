# Voice Ledger — Midnight Neon Design System

**Status:** Tokens implemented (`desktop/Sources/DesignSystem/`, builds clean).
Components and pages not yet built — those are Phase 1 step 1.3+, not approved.

Source: the visual brief supplied 2026-08, translated from its web framing into
a native macOS SwiftUI system. Where the brief conflicts with `CLAUDE.md` or
`docs/VOICE_LEDGER_SPEC.md`, this document records the conflict and how it was
resolved rather than silently picking one.

---

## 1. Translation notes — what changed and why

The brief was written for a web app. Several instructions have no native
equivalent, so they were translated rather than followed literally:

| Brief said | Native equivalent | Why |
|---|---|---|
| CSS variables / design tokens | Swift `enum` namespaces of `static let` | Same purpose — one definition site, no scattered literals |
| "Lucide" icon family | **SF Symbols** | Lucide is a web library. SF Symbols ships with macOS, has the outlined thin-to-medium stroke the brief asks for, and supports dynamic type and accessibility labels natively |
| `prefers-reduced-motion` | `@Environment(\.accessibilityReduceMotion)` | Same setting, native API. `VLMotion.respecting(_:_:)` wraps it |
| "browser zoom" readability | Dynamic Type | The macOS equivalent |
| Toasts / dropdowns / routing | Native alerts, menus, `NavigationSplitView` | Framework primitives, not web components |
| "8-pixel spacing system" | 8-**point** grid | Points, not pixels, on a Retina display |
| "Run existing linting/type checks" | `swift build` | No linter is configured yet; the module-boundary and secret-scan scripts are the existing checks |

**Barlow Condensed / Roboto Condensed** are not installed on macOS by default.
`VLTypography` uses the system font at `.width(.condensed)`, which gives the
condensed display character without depending on a font that may be absent.
If you later bundle Barlow Condensed, change `VLTypography` only.

---

## 2. Color

Implemented in `VLColor.swift`. All values from the brief, unchanged.

### The rule that matters most

**Accent colors and status colors are separate vocabularies.**

| Vocabulary | Colors | Means |
|---|---|---|
| **Accent** | cyan, cyan-bright, blue, teal, violet | Active nav, connection live, selected control, focus ring. Interaction state. |
| **Status** | green, amber, coral, a dedicated status-blue, violet, gray | What a check or finding *means*. Accounting semantics. |
| **Environment** | a dedicated near-black + a dedicated amber-adjacent stripe hue | Which QBO environment is active. Neither accent nor status — see §4c. |

Cyan glow on a selected row means "this row is selected." It does **not** mean
"this row is fine." That separation is the brief's own most important rule,
and it is now enforced structurally, not just by convention: `VLStatus.swift`
declares its three status hues (green/amber/coral) `private` to that file, and
`VLEnvironment.swift` does the same for its two environment hues. Neither file
can reference the other's constants — a compile error, not a lint warning.
See §4c for how this caught a real mistake.

### Status semantics (from the spec's color table)

| Status | Color + icon | Meaning |
|---|---|---|
| `.verified` | Green + checkmark | Checked and passed — **four preconditions, §3** |
| `.reviewNeeded` | Amber + magnifier | Human review required |
| `.urgent` | Coral + alert triangle | Urgent or materially risky |
| `.informational` | A dedicated status-blue (`#4FA3E8`) + info | Recommendation or opportunity |
| `.awaitingClient` | Violet + speech bubble | Waiting on client |
| `.notChecked` | Gray + clock | Stale, unavailable, or not checked |
| `.actionRequired` | Gray **dashed outline** + upload | Import or manual QBO work needed |

**`.informational` does not use `VLColor.blue` or `VLColor.cyan`/`cyanBright`.**
`VLColor.blue` fails WCAG AA as text on card surfaces (§9), and the accent
cyans would make "this is a recommendation" visually indistinguishable from
"this is selected" — the exact category error §4c fixes for environment,
caught here during implementation before it shipped. `.informational` gets its
own hue, `#4FA3E8`, private to `VLStatus.swift` alongside the other three
status colors, measuring 5.92:1 on `surfaceCard`.

`.notChecked` and `.actionRequired` share a hue, so they are differentiated by
**form**: `.actionRequired` renders as a dashed outline, `.notChecked` as a
filled pill. Hue alone would make them indistinguishable.

---

## 3. Green — the four preconditions

`CLAUDE.md` rule 5 and the spec both state green must never mean merely
"nothing was found." `VLStatus.verified` may only render when **all four** hold:

1. The required data was present
2. The check actually completed
3. The result is current (not stale)
4. No exception was found

Three enforcement layers, so this survives a careless afternoon:

- **Type level:** there is no `.success` case. The only green case is named
  `verified`, and reaching for it to mean "looks fine" reads wrong.
- **Rule engine:** `RuleOutcome` has three cases, not two —
  `.pass` / `.findings` / `.cannotEvaluate`. "Ran and found nothing" and
  "couldn't run" cannot collapse into one value
  (`docs/phase-0/08_RULE_ENGINE.md` §8.1).
- **UI:** `VLCoverageStrip` puts DATA AVAILABLE and CHECKS COMPLETED to the
  *left* of EXCEPTIONS FOUND, so a page answers "can I trust this screen?"
  before it answers "what did it find?"

`VLCoverageGap` carries the honest alternative copy — "Coverage incomplete,"
"Import required," "Extraction unreliable" — instead of "Passed."

---

## 4. Conflicts resolved

Three places where the brief and the accounting rules pulled against each
other. Flagging rather than silently choosing.

### 4a. "Positive/completed: teal or green"

The brief's status list offers green as a general positive. The spec does not
permit that. **Resolved:** green is reserved for `.verified` only. Teal is
demoted to an *accent* (used for Read-Only mode, Type B page accents, chart
series) and carries no status meaning. If you want to show "this finished,"
that is `.verified` and it must earn all four preconditions.

### 4b. Amber collision — sandbox vs. review-needed

The brief assigns amber to both "warning/review needed" **and** the SANDBOX
environment marker. A bookkeeper in sandbox would see amber constantly, which
would dull the amber that means "look at this."

**Resolved by form, not hue.** `VLEnvironmentBadge` renders sandbox with
**diagonal hazard stripes**; status pills are always solid or dashed-outline,
never striped. The stripe pattern appears nowhere else in the system, so
"striped amber = environment" and "solid amber = review needed" stay distinct
even at a glance from the far monitor.

### 4c. Which environment should be louder? — resolved 2026-08-16, owner decision

The brief says production is "restrained navy/cyan" and sandbox is the loud
one. First pass inverted that so production read serious via coral + a shield
icon — reasoning correctly that under `CLAUDE.md` rule 7 the dangerous state
is being in production without noticing, but picking the wrong instrument for
it.

**The problem with coral:** coral means `.urgent` — a finding that's urgent or
materially risky. Once live with real clients, production is the *permanent
normal state*, not an occasional alert. A coral badge sitting on screen every
working hour trains the eye to stop seeing coral, which is exactly the
amber/sandbox collision from §4b, recurring one level up: reusing a status hue
for something that isn't a status.

**Resolved: environment is a third vocabulary**, separate from both accent
(§2) and status (§3). It borrows no hue from either:

- **Production** renders as a **solid filled bar** — wider than any status
  pill, shield icon, primary text, on a dedicated near-black surface
  (`#050B14`, deliberately darker than the app background so it reads as its
  own surface rather than a chrome variant). Serious by **form and
  permanence**, not by borrowing danger red.
- **Sandbox** keeps the diagonal hazard-stripe chip from §4b — it already
  worked, appears nowhere else, and survives color-blind viewing.

Both remain unmistakable; neither steals from the status palette.

**Structural guard, not just a naming convention:** the three status hues
(`verified`/`reviewNeeded`/`urgent`) are declared `private` inside
`VLStatus.swift`. Environment's two hues (`productionSurface`,
`sandboxStripe`) are declared `private` inside `VLEnvironment.swift`. Neither
file can see the other's constants — verified directly: adding a line to
`VLEnvironment.swift` that reads `StatusHue.urgent` fails to compile with
*"'StatusHue' is inaccessible due to 'private' protection level."* A future
careless afternoon cannot reintroduce coral-as-environment; the compiler
refuses it.

During development the two are further separated by credentials, since the
dev backend physically cannot mint a production token
(`docs/phase-0/03_SECURITY_THREAT_MODEL.md` §3.8).

### 4d. Write-Enabled is not an error

The brief asks that Write-Enabled be "more serious and explicit, but should
not resemble an error state." `VLAccessMode.writeEnabled` uses amber, not
coral — coral is reserved for actual risk, and using it for a mode the user
deliberately turned on would train them to ignore real alerts.

---

## 5. Typography

| Role | Token | Family |
|---|---|---|
| Page title | `pageTitle()` | Condensed, bold, 28pt |
| Section heading | `sectionTitle()` | Condensed, semibold, 19pt |
| Large metric | `metricLarge()` | Condensed, bold, monospaced digits, 34pt |
| Card title | `cardTitle()` | Standard, semibold, 15pt |
| Body | `body()` | Standard, regular, 13pt |
| Label | `label()` | Standard, semibold, 11pt |
| Caption / provenance | `caption()` | Standard, regular, 11pt |
| Financial values | `tabularNumeric()` | Standard, monospaced digits, 13pt |
| Eyebrow (ALL CAPS) | `eyebrow()` + `.tracking(0.8)` | Standard, semibold, 10pt |

**Condensed type is display-only.** Never for paragraphs, inputs, or table
data — the brief is explicit and it is right: condensed body text in a
financial table is genuinely harder to read.

**Monospaced digits everywhere money appears.** Non-tabular figures jitter as
they update and make a column of dollars impossible to scan.

---

## 6. Layout, elevation, motion

- **8pt grid** with 2pt and 4pt half-steps for chip interiors and dense table
  cells, where a full step would waste space a bookkeeper needs.
- **Radii:** chip 6, control 8, card 12, panel 16.
- **Elevation is restrained.** `VLElevation.card` is barely lifted.
  `activeGlow` — the cyan illumination — is opt-in via `VLCard(isActive:)`
  and should be rare. If every card glows, a glowing card means nothing.
- **Motion 150–220ms.** No pulsing, flickering, rotating backgrounds, or
  animated circuit lines. `VLMotion.respecting(reduceMotion:_:)` returns `nil`
  under Reduce Motion, so honoring the setting is the default path.

---

## 7. Decorative technical detail

`VLColor.decorativeLine` is 6% opacity, deliberately near-invisible. Circuit
paths, dot grids, and node lines are permitted **only** where they explain a
real relationship:

- Ingestion pipeline (source → extract → verify → normalize → check)
- Month-end close dependency graph
- Finding provenance chains
- Reconciliation matching

**Never** behind tables, forms, long text, or routine settings screens. All
decorative graphics carry `.accessibilityHidden(true)`.

---

## 8. Accessibility

Built into the primitives rather than bolted on:

- `VLStatusPill` has **no initializer producing a bare colored dot** — the
  label is not optional. Status-by-color-alone is structurally impossible.
- Each pill collapses to one accessibility element reading
  "Status: Review needed" rather than announcing an SF Symbol name.
- Decorative stripes and accent rails are `.accessibilityHidden(true)`.
- Reduce Motion honored via `VLMotion`.
- **Text colors are contrast-checked, not just targeted.** See §9 — every
  declared text-on-surface pairing measures ≥4.5:1, verified directly against
  the actual code (not just the design intent).

---

## 9. Contrast — measured, fixed, and enforced (resolved 2026-08-16)

Two pairs were measured against WCAG 2.1's formula and failed AA for normal
text:

| Pair | Ratio | Verdict |
|---|---|---|
| `textMuted` (old `#71849B`) on `surfaceCard` | 4.19:1 | ❌ fails (4.5:1 required) |
| `textMuted` (old) on `surfaceElevated` | 4.43:1 | ❌ fails, marginal |
| `VLColor.blue` (`#2788D9`) on `surfaceCard` | 4.29:1 | ❌ fails as text |

**Fixes applied:**

1. **`textMuted` raised to `#7E92AA`.** Worst case (`surfaceCard`) now
   measures **5.03:1**. One token change, applies everywhere the token is used.
2. **`blue` is documented and enforced as non-text-safe.** `VLColor.swift`'s
   doc comment states it directly; it never appears in the "declared valid"
   catalog. It remains fine for borders, strokes, chart series, and icon
   fills, which only need 3:1.
3. **`.informational`'s status color is not `blue`, `cyan`, or `cyanBright`**
   — see §2. A dedicated `#4FA3E8` was chosen specifically to clear AA while
   staying visually distinct from both the accent-cyan family and the
   now-non-text-safe `blue`.

**Verified directly**, not just computed by hand: a scratch executable
importing `DesignSystem` and calling `VLContrast.auditAllPairs()` against the
actual compiled code returned **0 violations across all 45 declared pairs**,
matching an independent Node.js computation of the same WCAG formula run
first as a cross-check. Full ratio table available by running that audit
again — see `VLContrast.swift`'s doc comment.

**Enforced going forward, not just measured once:** `VLContrast.swift` is
production code (verified by `swift build`, not only by `swift test`) —
`auditAllPairs()` walks a declared catalog of every text/surface pairing the
system claims is valid and flags anything below 4.5:1.
`Tests/DesignSystemTests/ContrastTests.swift` asserts the catalog stays
empty of violations, plus a regression guard on `textMuted`'s specific ratio
and an explicit check that `blue` never re-enters the catalog. This closes
the original open item — contrast is now something CI checks, not something
remembered.

**Marginal pair worth flagging:** `violet` on `surfaceCard` measures
**4.52:1** — passes, but by the smallest margin of any pair in the catalog.
Not currently used for essential text (it's `.awaitingClient`'s status color,
always paired with an icon and label per §8), but worth knowing if it's ever
reused for something smaller or thinner.

---

## 10. Remaining open items

- **Condensed font substitution** — evaluate whether the system condensed
  width is close enough to the reference, or whether Barlow Condensed should
  be bundled.
- **§4c** — resolved; see that section. No longer open.
