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
struct WindowSnapshot: Codable, Equatable {
    let bundleId: String
    let appName: String
    let title: String
    let displayRole: DisplayRole?
    let normalizedFrame: NormalizedFrame?
    let absoluteFrame: CGRect
}
