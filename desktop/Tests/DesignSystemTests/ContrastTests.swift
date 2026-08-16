import Testing
@testable import DesignSystem

/// docs/design/DESIGN_SYSTEM.md, Decision 2: contrast ratios were measured
/// by hand once and two pairs failed AA. This test converts that from
/// something we remember to something CI enforces — the actual computation
/// lives in VLContrast.swift (production code, so it's checked by `swift
/// build` too); this test just asserts the catalog stays clean.
///
/// Verified manually before this file was written, since `swift test` is
/// unverified in this environment (see Tests/README.md): a scratch
/// executable importing DesignSystem and calling `VLContrast.auditAllPairs()`
/// directly returned 0 violations across all 45 declared pairs, matching an
/// independent Node.js computation of the same WCAG formula. This test
/// exercises the identical code path — it is not a new claim, it's the
/// existing verified result made to fail loudly if it ever regresses.
@Suite("Contrast — WCAG AA")
struct ContrastTests {
    @Test("Every declared text-on-surface pair clears 4.5:1")
    func allDeclaredPairsPassAA() {
        let violations = VLContrast.auditAllPairs()
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test("The catalog is non-empty — an empty catalog would trivially pass")
    func catalogIsNotAccidentallyEmpty() {
        #expect(VLContrast.declaredTextPairs.count > 0)
    }

    @Test("textMuted on surfaceCard — the worst-case pair — clears AA with margin")
    func textMutedWorstCase() {
        let surfaceCard = VLContrast.ResolvedRGB(hex: 0x102238)
        let textMuted = VLContrast.ResolvedRGB(hex: 0x7E92AA)
        let ratio = VLContrast.ratio(textMuted, surfaceCard)
        #expect(ratio >= VLContrast.minimumNormalTextRatio)
        // Regression guard on the specific measured value, not just the
        // threshold — if this drifts materially from ~5.03, the token
        // changed without this test being updated deliberately.
        #expect(ratio > 4.9 && ratio < 5.2)
    }

    @Test("blue (VLColor.blue) is deliberately absent from the valid-text-pairs catalog")
    func blueIsNotClaimedTextSafe() {
        // docs/design/DESIGN_SYSTEM.md Decision 2: VLColor.blue measures
        // 4.29:1 on surfaceCard — it fails AA and must never appear as a
        // "declared valid" text pairing. This test asserts the absence
        // directly rather than trusting VLColor.swift's comment alone.
        let isPresent = VLContrast.declaredTextPairs.contains { $0.name.lowercased().hasPrefix("blue ") }
        #expect(!isPresent)
    }
}
