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
| **Status** | green, amber, coral, blue, violet, gray | What a check or finding *means*. Accounting semantics. |

Cyan glow on a selected row means "this row is selected." It does **not** mean
"this row is fine." That separation is the brief's own most important rule and
it is enforced in code: `VLColor`'s status hues carry a comment directing
callers to `VLStatus` instead of using them raw.

### Status semantics (from the spec's color table)

| Status | Color + icon | Meaning |
|---|---|---|
| `.verified` | Green + checkmark | Checked and passed — **four preconditions, §3** |
| `.reviewNeeded` | Amber + magnifier | Human review required |
| `.urgent` | Coral + alert triangle | Urgent or materially risky |
| `.informational` | Blue + info | Recommendation or opportunity |
| `.awaitingClient` | Violet + speech bubble | Waiting on client |
| `.notChecked` | Gray + clock | Stale, unavailable, or not checked |
| `.actionRequired` | Gray **dashed outline** + upload | Import or manual QBO work needed |

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

### 4c. Which environment should be louder?

The brief says production is "restrained navy/cyan" and sandbox is the loud
one. Worth a deliberate decision, because it is backwards from a pure risk
standpoint: under `CLAUDE.md` rule 7 the *dangerous* state is being in
production without realizing it.

**Resolved:** both are unmistakable, but they signal different things —
sandbox is loud because it means "nothing here is real," production uses
coral + a shield icon because it means "this is a client's actual books."
Production is not visually *quiet*; it is visually *serious*. During
development the two are further separated by credentials, since the dev
backend physically cannot mint a production token
(`docs/phase-0/03_SECURITY_THREAT_MODEL.md` §3.8).

**This one is worth your explicit sign-off** — it is the only place I chose
against the brief's literal instruction.

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
- Text colors target WCAG AA against the navy surfaces. **Verify with a
  contrast checker once real screens exist** — I have not measured these
  ratios, and the brief's palette was supplied as-is.

---

## 9. Open items

- **§4c** (which environment is louder) needs your sign-off.
- **Contrast ratios unmeasured.** `textMuted` (#71849B) on `surfaceCard`
  (#102238) is the pair most likely to fall short of AA for small text.
  Measure before shipping any screen that uses it for essential information.
- **Condensed font substitution** — evaluate whether the system condensed
  width is close enough to the reference, or whether Barlow Condensed should
  be bundled.
