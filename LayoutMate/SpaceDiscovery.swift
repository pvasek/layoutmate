import AppKit
import CoreGraphics

/// Wrappers around private CGS routines for reading and switching macOS Spaces.
///
/// We use:
///   - `CGSCopyManagedDisplaySpaces` (READ) — list current and all Spaces per display.
///     Stable across macOS releases for years; what Hammerspoon's hs.spaces uses.
///   - `CGSManagedDisplaySetCurrentSpace` (WRITE-but-only-switch) — set which Space
///     is foregrounded on a given display. This is the *goto* family; not the
///     *move-window-between-Spaces* family that regressed in Sequoia 15.0.
///
/// Notably *not* used: `CGSAddWindowsToSpaces` / `CGSMoveWindowsToManagedSpace`
/// — those are how you'd move *individual* windows to other Spaces, and that's
/// what Apple broke. We never touch them. Switching the active Space and then
/// letting macOS decide what's visible works fine.
///
/// All callers tolerate `nil` / no-op return — if Apple ever breaks or removes
/// these symbols on a future macOS, snapshots quietly lose their spaceID and
/// the app degrades to single-Space-at-a-time behavior instead of crashing.
enum SpaceDiscovery {
    typealias SpaceID = UInt64

    /// Per-display Space state, captured in one call.
    struct DisplaySpaces {
        let displayID: CGDirectDisplayID
        let displayUUID: String
        let currentSpaceID: SpaceID
        /// All Space IDs on this display, in the order macOS reports them
        /// (which matches Mission Control's left-to-right order in practice).
        let allSpaceIDs: [SpaceID]
    }

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

    /// Full Space inventory for the given displays. Empty if the private API failed.
    static func enumerate(displayIDs: [CGDirectDisplayID]) -> [DisplaySpaces] {
        guard let entries = managedDisplaySpaces() else { return [] }

        var result: [DisplaySpaces] = []
        for cgID in displayIDs {
            guard let uuid = uuidString(for: cgID) else { continue }
            for entry in entries {
                guard let id = entry["Display Identifier"] as? String, id == uuid,
                      let current = entry["Current Space"] as? [String: Any],
                      let currentID = current["id64"] as? SpaceID,
                      let spaces = entry["Spaces"] as? [[String: Any]]
                else { continue }
                let allIDs = spaces.compactMap { $0["id64"] as? SpaceID }
                result.append(DisplaySpaces(
                    displayID: cgID,
                    displayUUID: uuid,
                    currentSpaceID: currentID,
                    allSpaceIDs: allIDs
                ))
            }
        }
        return result
    }

    /// Switches the given display so the named Space is foregrounded. Asynchronous on
    /// macOS's side — the animation takes ~500ms, so callers should wait before assuming
    /// the switch has settled.
    static func setCurrentSpace(_ spaceID: SpaceID, on displayUUID: String) {
        let cid = _CGSDefaultConnection()
        CGSManagedDisplaySetCurrentSpace(cid, displayUUID as CFString, spaceID)
    }

    // MARK: - Private helpers

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

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ displayUUID: CFString, _ spaceID: UInt64)
