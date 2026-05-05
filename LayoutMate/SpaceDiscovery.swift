import AppKit
import CoreGraphics

/// Wrappers around the private CGS routine that exposes which macOS Space is currently
/// active on each connected display. We only *read* — never move windows between Spaces
/// or switch Spaces ourselves. The read side has been stable across macOS releases for
/// years (it's what Hammerspoon's `hs.spaces` uses); the write side regressed in
/// Sequoia 15.0 and is excluded from v3 by design.
///
/// All callers tolerate `nil` return from this module — if Apple ever breaks or removes
/// these symbols on a future macOS, snapshots quietly lose their spaceID and the app
/// degrades to v2 behavior (single-Space save/restore) instead of crashing.
enum SpaceDiscovery {
    typealias SpaceID = UInt64

    /// The Space ID currently foregrounded on the given display, or `nil` if the private
    /// API call failed or the display couldn't be matched.
    static func currentSpaceID(for displayID: CGDirectDisplayID) -> SpaceID? {
        guard let uuid = uuidString(for: displayID),
              let displays = managedDisplaySpaces()
        else { return nil }

        for entry in displays {
            guard let id = entry["Display Identifier"] as? String, id == uuid else { continue }
            if let current = entry["Current Space"] as? [String: Any],
               let id64 = current["id64"] as? SpaceID {
                return id64
            }
        }
        return nil
    }

    /// Returns the raw [{"Display Identifier": ..., "Current Space": {...}, "Spaces": [...]}, ...]
    /// listing as a Swift dictionary array, or nil on failure.
    private static func managedDisplaySpaces() -> [[String: Any]]? {
        let cid = _CGSDefaultConnection()
        let array = CGSCopyManagedDisplaySpaces(cid).takeRetainedValue()
        return array as? [[String: Any]]
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuidUnmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let uuid = uuidUnmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

// MARK: - Private CGS bindings

private typealias CGSConnectionID = UInt32

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>
