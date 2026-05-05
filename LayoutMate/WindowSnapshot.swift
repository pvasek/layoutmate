import Foundation

/// Frame stored as fractions of its host display's frame, in AX/CG coords.
/// This is what makes restore resolution-independent: a window saved at 50%×30%
/// of a 4K screen lands at 50%×30% of the 1080p screen it's restored on.
struct NormalizedFrame: Codable, Equatable {
    let x: Double       // origin x as a fraction of host display width
    let y: Double       // origin y as a fraction of host display height
    let width: Double   // window width as a fraction of host display width
    let height: Double  // window height as a fraction of host display height
}

/// One window's identity and on-screen geometry at the moment of capture.
///
/// At restore time the placement is resolved in this priority order:
/// 1. `displayRole` + `normalizedFrame` — find a current display in that role and place
///    proportionally. If exact role isn't available, fall down to the next-best (see
///    `WindowRestorer.computeTargetFrame`).
/// 2. `absoluteFrame` — last-resort fallback when no role info is usable.
///
/// `spaceID` records which macOS Space the window was on at capture. Restore filters to
/// snapshots whose `(displayRole, spaceID)` matches what's currently foregrounded on the
/// corresponding display, so the user can swipe between Spaces and Restore on each. If
/// the private Space-readback API is unavailable, this stays `nil` and the per-Space
/// filter is skipped (degrades to v2 behavior).
struct WindowSnapshot: Codable, Equatable {
    let bundleId: String
    let appName: String
    let title: String
    let displayRole: DisplayRole?
    let spaceID: UInt64?
    let normalizedFrame: NormalizedFrame?
    let absoluteFrame: CGRect
}
