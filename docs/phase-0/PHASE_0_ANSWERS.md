# Answers to OPEN_QUESTIONS.md

Reviewed the Phase 0 plan. Approving the seven architectural decisions in
`00_OVERVIEW.md` as written — D1 (three outcomes), D2 (database per realm),
D3 (watermark staleness), D4 (unknown-state journal), D5 (operation catalog),
D6 (reports as a distinct data class), D7 (gated slice write path). No changes.

Answers below in order.

---

## Q1 — Prototype repo

**[FILL IN: paste your GitHub URL or local path here.]**

Treat it as conceptual reference only, per the original framing — near-zero code
reuse expected. What I actually want from deliverable 1 is section D of your
outline: the capability claims to re-verify. The prototype is a record of which
QBO endpoints returned useful data in practice, and those rows should enter §2 as
`ASSUMED (prototype-observed)` and get priority in the spike queue.

If sections A–C turn out to be thin because the builder output is mostly
scaffolding, say so and move on. Don't pad the inventory.

---

## Q2 — Backend hosting

**A small managed container.** Agreed with your recommendation.

Constraints: it needs a stable public HTTPS endpoint, real logs, and
straightforward secret storage. Cost matters more than scale — this serves one
operator and a handful of clients.

If webhooks turn out to be awkward to configure at first, **ship CDC-polling-only
and treat webhooks as a later latency optimization.** Per your own note, polling
is the correctness path anyway; I'd rather have a working read-only sync sooner
than a webhook endpoint I'm debugging in week one.

---

## Q3 — Single operator

**Confirmed single operator. Stop hedging.**

One caveat worth recording rather than designing for: I expect to bring on help
eventually — likely offshore staff — but that is far enough out that designing
for it now would be speculative. When it happens, treat multi-operator as its own
phase with its own design pass. Don't pre-build coordination for it, and don't
contort the current design to leave room. Just note in `07_CLIENT_ISOLATION.md`
which specific mechanisms would need revisiting (concurrent scope access,
per-entity write serialization across processes, `ApprovalRecord.approvedBy`) so
the future work is scoped rather than discovered.

---

## Q4 — Minimum macOS version

**[CHECK YOUR MAC: Apple menu → About This Mac. Report the version.]**

Target **macOS 15+** unless my machine is older. The `RecognizeDocumentsRequest`
difference is material for Tier 2 OCR on financial statements — tables and
reading order understood natively versus us clustering bounding boxes — and worse
Tier 2 means more Tier 3 escalations, which means more client documents leaving
my Mac. That is the wrong direction on the one privacy property the import path
gives me.

If my machine is on 14, tell me what upgrading buys in concrete terms before I do
it, and design Tier 2 with the fallback path in the meantime.

---

## Q5 — Locale and sales tax mode

**US only. Automated Sales Tax only.**

All clients will be US-based, and I'm not taking on legacy-manual-tax companies
in v1. Scope Page 9 to AST and mark legacy mode **explicitly unsupported** rather
than untested — I'd rather the page refuse to run than produce confidently wrong
findings against a mode it wasn't built for.

Keep the mode detection gate you specified. If a client's file turns out to be
legacy mode, Page 9 should render `.cannotEvaluate` with a clear reason, not
attempt AST-shaped rules.

---

## Q6 — Client count

**Tens. Your assumption is correct.**

I currently have zero clients — I'm building this before taking on my first. The
realistic ceiling for the foreseeable future is tens, not hundreds. Design the
Firm Cockpit fan-out for that and don't build a summary cache until there's a
measured reason to.

---

## Q7 — Materiality defaults

Start with a **low flat absolute floor — $25 — and no percentage-of-revenue
component by default.**

Reasoning: this is bookkeeping cleanup, not audit. A duplicate expense is an
error regardless of size, and a percentage floor scaled to revenue would suppress
small duplicates on larger clients, which is exactly backwards for what this tool
is for. I'd rather see too much early and tune per client than silently miss
things while I'm still learning what normal looks like.

**Use the `accountOverrides` mechanism for cash and clearing accounts** with a
tighter floor — treat any difference there as material. Those are the accounts
where a small unexplained amount usually indicates a structural problem rather
than a rounding artifact.

Since `MaterialityPolicy` is per-client, versioned, and part of the evidence
watermark, I can raise the floor per client once I know their transaction volume.
Make it easy to edit per client from the UI, and make sure the activity log
records every change — I want to be able to explain later why a finding appeared
or stopped appearing.

---

## Q8 — Cross-account duplicates

**Keep `VL-DUP-EXP-001` as designed — same payment account required.**

But add a separate rule to the backlog: **`VL-DUP-EXP-002`, cross-account
duplicate candidate** — same vendor, same amount, same or near date, *different*
payment account, `confidence: .medium` at best. Phase 2, not the slice.

The real-world case is paying the same bill from checking and then again from a
card, which does happen and is worth catching. But it's noisier, it's a different
false-positive profile, and mixing it into the first slice would widen the thing
whose whole value is being narrow. Separate rule, separate fixtures, separate
tuning.

---

## Q9 — Phase 0 reading

**You read it correctly.** "Build this app please" was loose phrasing on my part;
the attached prompt was the actual instruction, and stopping at the plan was
right. Don't start Phase 1 implementation until I say so explicitly.

---

## The two things you did without asking

**Renaming `docs:` → `docs`** — correct, thank you. That was my typo.

**Git** — yes, initialize it. Do it now, before any Phase 1 code:

```bash
git init && git add -A && git commit -m "Phase 0: spec, constraints, architecture plan"
```

Everything about the review workflow, rule versioning, and matrix regeneration
assumes diffs. Also add a `.gitignore` that excludes anything credential-shaped
before the first commit that could contain one — I want it impossible to commit a
token by accident, not merely unlikely.

---

## What I want next

Not implementation yet. Two things first:

1. **Deliverable 1** against the real repo once I paste the path above.
2. **The spike queue as an ordered, runnable list** — the specific sandbox tests
   from §2.8's waves, ordered so the highest-consequence unknowns settle first.
   The `Purchase` void question from §11.1 goes at the front, since the vertical
   slice's write path branches on it.

Then I'll approve Phase 1 step by step against the gate table in `00_OVERVIEW.md`.
