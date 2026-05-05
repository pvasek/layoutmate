import Foundation

/// Whole-app persistent state, stored as a single JSON file in Application Support.
///
/// `displayRoles` maps each known external display's hardware fingerprint to its assigned
/// slot number (1-indexed). Built-in displays are not in this map; they're auto-classified.
///
/// `layout` is the single saved layout, or `nil` if the user has never hit Save.
struct StoreData: Codable, Equatable {
    var displayRoles: [String: Int]
    var layout: Layout?

    static let empty = StoreData(displayRoles: [:], layout: nil)
}

enum LayoutStore {
    private static var directory: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("LayoutMate", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { directory.appendingPathComponent("store.json") }
    private static var legacyV1URL: URL { directory.appendingPathComponent("layout.json") }

    /// Returns the persisted store, or `.empty` on missing or undecodable file.
    /// Cleans up any v1-era `layout.json` so it doesn't linger as dead data.
    static func load() -> StoreData {
        try? FileManager.default.removeItem(at: legacyV1URL)

        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(StoreData.self, from: data)) ?? .empty
    }

    static func save(_ store: StoreData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: .atomic)
    }
}
