import AppKit
import CoreGraphics

/// A connected display, before role classification. `isBuiltIn` is the OS's verdict, the
/// only piece of role info we get for free. Externals get their slot assigned later.
struct RawDisplay {
    let identity: DisplayIdentity
    let screen: NSScreen
    let frame: CGRect       // top-left global / AX coords
    let localizedName: String
    let isBuiltIn: Bool
}

/// A connected display with its role resolved.
struct Display {
    let identity: DisplayIdentity
    let screen: NSScreen
    let frame: CGRect
    let localizedName: String
    let isBuiltIn: Bool
    let role: DisplayRole
}

enum DisplayDiscovery {
    /// Enumerates currently-connected displays without assigning external slots.
    static func currentDisplays() -> [RawDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let cgID = displayID(for: screen) else { return nil }
            let identity = DisplayIdentity(
                vendor: CGDisplayVendorNumber(cgID),
                product: CGDisplayModelNumber(cgID),
                serial: CGDisplaySerialNumber(cgID)
            )
            return RawDisplay(
                identity: identity,
                screen: screen,
                frame: Geometry.topLeftFrame(of: screen),
                localizedName: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(cgID) != 0
            )
        }
    }

    /// Resolves each raw display's role using the persisted slot map. Externals not yet in
    /// the map get auto-assigned the next free slot — the returned `roles` reflects those
    /// additions, and the caller is expected to persist it.
    static func classify(_ raws: [RawDisplay], roles: [String: Int]) -> (displays: [Display], roles: [String: Int]) {
        var updated = roles
        let usedSlots = Set(updated.values)
        var nextSlot = (usedSlots.max() ?? 0) + 1

        for raw in raws where !raw.isBuiltIn {
            if updated[raw.identity.fingerprint] == nil {
                updated[raw.identity.fingerprint] = nextSlot
                nextSlot += 1
            }
        }

        let displays = raws.map { raw -> Display in
            let role: DisplayRole
            if raw.isBuiltIn {
                role = .builtIn
            } else if let slot = updated[raw.identity.fingerprint] {
                role = .external(slot: slot)
            } else {
                // Should be unreachable given the loop above; guard against it anyway.
                role = .external(slot: nextSlot)
            }
            return Display(
                identity: raw.identity,
                screen: raw.screen,
                frame: raw.frame,
                localizedName: raw.localizedName,
                isBuiltIn: raw.isBuiltIn,
                role: role
            )
        }

        return (displays, updated)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID
    }
}
