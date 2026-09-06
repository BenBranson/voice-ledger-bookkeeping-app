import SwiftUI

/// Sidebar section colors — a fourth vocabulary, alongside Accent, Status,
/// and Environment (see `VLColor.swift`'s own doc comment on why those two
/// are kept separate). This one exists purely to help a reader tell one
/// workflow stage apart from another at a glance while scanning down the
/// sidebar — it carries no accounting meaning, and no case here may be
/// reached for anywhere status (`VLStatus`) or environment (`VLEnvironment`)
/// meaning is required.
///
/// Owner directive (2026-09-06): the sidebar read as plain white-on-navy
/// with no way to tell one workflow section from another at a glance —
/// "the left panel is currently just white font." `VLColor.cyan` and
/// `.violet` are reused deliberately for OVERVIEW and AI respectively
/// (their existing accent meaning — "active/live" and "AI affordance" —
/// already lines up with what those two sections are), and
/// `VLColor.teal` for CLOSE (already "demoted to accent, no status
/// meaning" per `VLColor.swift`, so reusing it here adds no new
/// ambiguity). CLEANUP, REPORTS, and CLIENT get new hues that avoid every
/// value `VLStatus`'s private `StatusHue` already uses (green/amber/coral/
/// status-blue), so a colored sidebar label never gets mistaken for an
/// accounting status. SETUP is deliberately desaturated (reuses
/// `VLColor.textMuted`) — config screens shouldn't compete for attention
/// with the workflow sections above them.
public enum VLNavColor {
    public static let overview = VLColor.cyan
    /// A magenta distinct from every reserved hue — chosen bright enough to
    /// read clearly on the dark sidebar without drifting into coral
    /// (`#F06472`, reserved for `.urgent`).
    public static let cleanup = Color(hex: 0xFF5FA8)
    public static let close = VLColor.teal
    /// An indigo distinct from both `VLColor.blue` (non-text-safe) and
    /// `VLColor.violet` (reserved for AI below).
    public static let reports = Color(hex: 0x8C9EFF)
    /// A warm orange distinct from `.reviewNeeded`'s amber (`#F4B860`) —
    /// noticeably redder/deeper so the two are never confused at a glance.
    public static let client = Color(hex: 0xFF8A3D)
    public static let ai = VLColor.violet
    public static let setup = VLColor.textMuted

    /// Looked up by section title (`SidebarSection.title`) rather than a
    /// dedicated enum — the sidebar's sections are already a flat
    /// `[SidebarSection]` list keyed by title string; adding a parallel
    /// enum just to key colors would be a second source of truth for the
    /// same seven names.
    public static func forSection(_ title: String) -> Color {
        switch title {
        case "OVERVIEW": return overview
        case "CLEANUP": return cleanup
        case "CLOSE": return close
        case "REPORTS": return reports
        case "CLIENT": return client
        case "AI": return ai
        case "SETUP": return setup
        default: return VLColor.textSecondary
        }
    }
}
