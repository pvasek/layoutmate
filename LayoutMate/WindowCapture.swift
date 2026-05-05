import AppKit
import ApplicationServices

enum WindowCapture {
    enum CaptureError: Error, LocalizedError {
        case notTrusted
        var errorDescription: String? {
            switch self {
            case .notTrusted: return "Accessibility permission not granted"
            }
        }
    }

    /// Snapshots every visible (non-minimized) window of every regular running application,
    /// excluding LayoutMate itself. Each window is tagged with the role of its host display
    /// and its proportional frame within that display's bounds.
    static func capture(displays: [Display]) throws -> Layout {
        guard AXIsProcessTrusted() else { throw CaptureError.notTrusted }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var snapshots: [WindowSnapshot] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  app.processIdentifier != ownPID
            else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let appName = app.localizedName ?? bundleId

            for window in AX.windows(of: appElement) {
                if AX.bool(window, kAXMinimizedAttribute) == true { continue }
                guard let frame = AX.frame(of: window) else { continue }
                if frame.width < 1 || frame.height < 1 { continue }

                let title = AX.string(window, kAXTitleAttribute) ?? ""
                let host = hostDisplay(for: frame, in: displays)
                let normalized = host.map { normalize(frame, to: $0.frame) }

                snapshots.append(WindowSnapshot(
                    bundleId: bundleId,
                    appName: appName,
                    title: title,
                    displayRole: host?.role,
                    normalizedFrame: normalized,
                    absoluteFrame: frame
                ))
            }
        }

        return Layout(savedAt: Date(), windows: snapshots)
    }

    private static func hostDisplay(for frame: CGRect, in displays: [Display]) -> Display? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = displays.first(where: { $0.frame.contains(center) }) {
            return containing
        }
        // Fall back to the display this frame intersects most.
        var best: (display: Display, area: CGFloat)?
        for display in displays {
            let inter = display.frame.intersection(frame)
            let area = inter.width * inter.height
            if area > 0, area > (best?.area ?? 0) {
                best = (display, area)
            }
        }
        return best?.display
    }

    private static func normalize(_ frame: CGRect, to displayFrame: CGRect) -> NormalizedFrame {
        NormalizedFrame(
            x: (frame.minX - displayFrame.minX) / displayFrame.width,
            y: (frame.minY - displayFrame.minY) / displayFrame.height,
            width: frame.width / displayFrame.width,
            height: frame.height / displayFrame.height
        )
    }
}
