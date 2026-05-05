import Foundation

/// A stable hardware-level identifier for a single display, derived from EDID-style
/// vendor / product / serial numbers via Core Graphics. Survives unplug-replug, reboots,
/// and macOS rearrangements. Some displays expose `serial == 0` (Apple built-in panels and
/// some third-party monitors that don't put a serial in EDID), in which case two physically
/// distinct units of the same model become indistinguishable — see callers for fallbacks.
struct DisplayIdentity: Codable, Hashable {
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32

    var fingerprint: String {
        String(format: "%08x-%08x-%08x", vendor, product, serial)
    }
}
