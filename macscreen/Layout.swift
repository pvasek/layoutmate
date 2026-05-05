import Foundation

/// One saved arrangement of windows. There is exactly one of these in the store at a time
/// (Save overwrites). Each window inside knows its display role and proportional frame, so
/// the same layout adapts to whatever hardware is currently connected.
struct Layout: Codable, Equatable {
    let savedAt: Date
    let windows: [WindowSnapshot]
}
