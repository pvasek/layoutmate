import Foundation

/// The semantic position of a display in the user's setup.
///
/// `builtIn` is auto-detected from the OS; the user never assigns it.
/// `external` slots are 1-indexed and user-controlled — the first time a new external is
/// seen we auto-assign the next free slot, but the user can reassign at will from the menu.
enum DisplayRole: Codable, Hashable {
    case builtIn
    case external(slot: Int)

    var displayLabel: String {
        switch self {
        case .builtIn: return "Built-in"
        case .external(let slot): return "External \(slot)"
        }
    }
}
