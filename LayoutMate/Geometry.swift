import AppKit

/// Coordinate-space helpers shared between capture and restore.
///
/// macOS has two coordinate systems:
///   - **Cocoa / NSScreen**: origin at bottom-left of the primary display, y goes up.
///   - **AX / CG global**:   origin at top-left  of the primary display, y goes down.
///
/// We keep all stored frames in AX/CG coords. These helpers convert NSScreen frames into the
/// same space so we can compare and clamp consistently.
enum Geometry {
    static func topLeftFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        let primaryHeight = primary.frame.height
        let f = screen.frame
        return CGRect(x: f.minX,
                      y: primaryHeight - f.maxY,
                      width: f.width,
                      height: f.height)
    }

    /// Top-left/CG-coords union of every currently connected screen.
    static func unionOfAllScreens() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union(topLeftFrame(of: $1)) }
    }
}
