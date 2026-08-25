// swift-tools-version: 6.0
import PackageDescription

// Module layout mirrors docs/VOICE_LEDGER_SPEC.md's Architecture > Core layers,
// and target dependencies encode the one rule that section states as absolute:
// Core never imports Integrations. Scripts/check-module-boundaries.sh enforces
// this by source scan; ArchitectureTests/ModuleBoundaryTests.swift runs it as
// part of `swift test`, so a violation fails CI rather than surviving to review.
let package = Package(
    name: "VoiceLedger",
    platforms: [
        .macOS(.v15)   // provisional per docs/phase-0/OPEN_QUESTIONS.md Q4 — confirm against the actual installed OS
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "IntegrationsQuickBooks", targets: ["IntegrationsQuickBooks"]),
        .library(name: "IntegrationsImports", targets: ["IntegrationsImports"]),
        .library(name: "Staging", targets: ["Staging"]),
        .library(name: "Voice", targets: ["Voice"]),
        .library(name: "DB", targets: ["DB"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "VoiceLedgerUI", targets: ["VoiceLedgerUI"]),
        .library(name: "Exporting", targets: ["Exporting"]),
        .executable(name: "voiceledger-devtool", targets: ["VoiceLedgerDevTool"]),
        .executable(name: "VoiceLedgerApp", targets: ["VoiceLedgerApp"])
    ],
    targets: [
        // /core — platform-agnostic. Zero dependencies, by design. This target
        // must never depend on IntegrationsQuickBooks, IntegrationsImports, or
        // any other module below it in the list.
        .target(name: "Core", path: "Sources/Core", exclude: ["README.md"]),

        // /integrations/quickbooks — this is the DESKTOP-SIDE client for our
        // own thin backend (see docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4).
        // It never talks to QBO directly and holds no QBO or Claude secret.
        .target(name: "IntegrationsQuickBooks", dependencies: ["Core"], path: "Sources/Integrations/QuickBooks"),

        // /integrations/imports — deferred; stub only until its approved
        // build step (Build Order §4 in docs/VOICE_LEDGER_SPEC.md).
        .target(name: "IntegrationsImports", dependencies: ["Core"], path: "Sources/Integrations/Imports"),

        // /staging — deferred; stub only (docs/phase-0/10_STAGING_APPROVAL_AUDIT.md).
        .target(name: "Staging", dependencies: ["Core"], path: "Sources/Staging"),

        // /voice — deferred deliberately last per Build Order §12.
        .target(name: "Voice", dependencies: ["Core"], path: "Sources/Voice"),

        // /db — Phase 1 step 1.6: ClientStore.swift, a real (scoped-down)
        // per-realm store. See its doc comment for the relationship to
        // docs/phase-0/07_CLIENT_ISOLATION.md §7.1's SQLite-per-realm design.
        .target(name: "DB", dependencies: ["Core"], path: "Sources/DB"),

        // Isolation and reconciliation tests for ClientStore. No dependency
        // on IntegrationsQuickBooks — a violation here would mean /db leaked
        // toward /integrations, which CLAUDE.md's architecture boundaries
        // forbid just as much as the reverse.
        .testTarget(name: "DBTests", dependencies: ["DB", "Core"], path: "Tests/DBTests"),

        // Design tokens and the smallest primitives that enforce them.
        // Deliberately has NO dependency on Core: these are pure presentation
        // constants, and Core must stay platform-agnostic (it cannot import
        // SwiftUI). The mapping from domain types (Severity, Coverage) to
        // VLStatus belongs in the UI layer, once those domain types exist.
        // See docs/design/DESIGN_SYSTEM.md.
        .target(name: "DesignSystem", dependencies: [], path: "Sources/DesignSystem",
                exclude: ["README.md"]),

        // CLI used ONLY to verify gate conditions: Phase 1 step 1.2's health
        // check, and (as of 2026-08-16) a live-sandbox sync-and-evaluate
        // diagnostic for step 1.6's slice (docs/VOICE_LEDGER_HANDOFF.md §13's
        // "no live end-to-end run happened" gap). This is NOT the Connection
        // Page or the real app (that's VoiceLedgerApp) — it is the smallest
        // thing that can prove a gate against real data, text-only, no UI.
        .executableTarget(
            name: "VoiceLedgerDevTool",
            dependencies: ["Core", "IntegrationsQuickBooks", "IntegrationsImports", "DB", "Exporting"],
            path: "Sources/VoiceLedgerDevTool"
        ),

        // Phase 1 step 1.6's minimal UI (docs/phase-0/11_VERTICAL_SLICE.md
        // §11.2's "UI — minimum viable, and no more"): findings list, finding
        // detail, guided-procedure/attestation view, activity log view. Maps
        // Core's domain types (Severity, Coverage) to DesignSystem's VLStatus
        // vocabulary — that mapping belongs here, not in Core (which cannot
        // import SwiftUI) and not in DesignSystem (pure presentation tokens,
        // no domain knowledge).
        .target(
            name: "VoiceLedgerUI",
            dependencies: ["Core", "DesignSystem"],
            path: "Sources/VoiceLedgerUI"
        ),

        // Gauntlet Loop, Gauntlet C round 2 (2026-08-24): a fresh critic
        // found a real CLAUDE.md rule 5 violation (a coverage-strip column
        // could render green on stale/not-yet-synced data) and could only
        // prove it by building a TEMPORARY test target, since nothing in
        // this package could previously exercise VoiceLedgerUI's own
        // domain-to-VLStatus mapping logic directly — every prior check of
        // it was trace-only. Made permanent so this class of bug (a
        // rendering computation that silently drifts from the honesty
        // invariants) has a real test target watching it going forward.
        .testTarget(
            name: "VoiceLedgerUITests",
            dependencies: ["VoiceLedgerUI", "Core", "DesignSystem"],
            path: "Tests/VoiceLedgerUITests"
        ),

        // CSV/XLSX/PDF export — takes a Core `ExportTable` and produces file
        // bytes. XLSX is a hand-rolled minimal OOXML writer (no third-party
        // zip/spreadsheet dependency): the ZIP container uses STORED
        // (uncompressed) entries, which is a fully valid zip per spec and
        // sidesteps needing a DEFLATE implementation entirely, since this
        // writes files rather than reading arbitrary ones. PDF uses
        // CoreGraphics/AppKit, both part of the macOS SDK already targeted.
        .target(
            name: "Exporting",
            dependencies: ["Core"],
            path: "Sources/Exporting"
        ),

        .testTarget(
            name: "ExportingTests",
            dependencies: ["Exporting", "Core"],
            path: "Tests/ExportingTests"
        ),

        // The actual running app: wires QBOSyncClient -> RuleEngine ->
        // ClientStore -> VoiceLedgerUI for the slice's real end-to-end path.
        // NOT visually verified in this session — no screenshot tool for a
        // native macOS window was available; see the final report.
        .executableTarget(
            name: "VoiceLedgerApp",
            dependencies: ["Core", "IntegrationsQuickBooks", "IntegrationsImports", "DB", "DesignSystem", "VoiceLedgerUI", "Exporting"],
            path: "Sources/VoiceLedgerApp"
        ),

        // `swift test` requires full Xcode (Testing.framework isn't part of
        // the standalone Command Line Tools) — see Tests/README.md for that
        // history. Verified 2026-08-16 with Xcode installed: 12/12 passing.
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),

        // T0 structural tests (docs/phase-0/12_TEST_STRATEGY.md §12.2) —
        // architecture invariants that fail a build rather than survive to review.
        .testTarget(
            name: "ArchitectureTests",
            dependencies: ["Core", "IntegrationsQuickBooks"],
            path: "Tests/ArchitectureTests"
        ),

        // Normalization tests for QBOSyncClient — synthetic JSON in, no
        // network, no live sandbox. docs/phase-0/11_VERTICAL_SLICE.md §11.2's
        // "Normalize to LedgerTransaction" step, tested against the real raw
        // shape confirmed by Wave 1's testPurchasesRead.
        .testTarget(
            name: "IntegrationsQuickBooksTests",
            dependencies: ["IntegrationsQuickBooks", "Core"],
            path: "Tests/IntegrationsQuickBooksTests"
        ),

        // Contrast audit (docs/design/DESIGN_SYSTEM.md, Decision 2). The
        // underlying computation (VLContrast.swift) is production code and
        // is build-verified; this test target asserts the catalog stays
        // clean going forward.
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemTests"
        ),

        // Universal Ingestion Tier 1 (docs/phase-0/09_INGESTION_PIPELINE.md
        // §9.3) — CSV parsing and bank-statement normalization, no network,
        // no live sandbox.
        .testTarget(
            name: "IntegrationsImportsTests",
            dependencies: ["IntegrationsImports", "Core"],
            path: "Tests/IntegrationsImportsTests"
        )
    ]
)
