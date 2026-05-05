import AppKit
import ApplicationServices

enum WindowRestorer {
    struct Result {
        var attempted: Int = 0
        var moved: Int = 0
        var skipped: Int = 0
    }

    /// Best-effort restore: walks each saved window, finds a matching live window of the same
    /// app, computes its target frame for the *current* display set (proportionally where
    /// possible, falling back if the original role isn't available), and moves it.
    static func restore(_ layout: Layout, currentDisplays: [Display]) -> Result {
        var result = Result()

        // De-duplicate: multiple NSRunningApplication instances can share a bundle id.
        let runningByBundle: [String: NSRunningApplication] = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> (String, NSRunningApplication)? in
                    guard let id = app.bundleIdentifier else { return nil }
                    return (id, app)
                },
            uniquingKeysWith: { first, _ in first }
        )

        let snapshotsByBundle = Dictionary(grouping: layout.windows, by: { $0.bundleId })

        for (bundleId, snapshots) in snapshotsByBundle {
            result.attempted += snapshots.count

            guard let app = runningByBundle[bundleId] else {
                result.skipped += snapshots.count
                continue
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var available = AX.windows(of: appElement)

            for snapshot in snapshots {
                guard let idx = matchIndex(for: snapshot, in: available) else {
                    result.skipped += 1
                    continue
                }
                let window = available.remove(at: idx)
                let target = computeTargetFrame(for: snapshot, currentDisplays: currentDisplays)
                if AX.setFrame(target, on: window) {
                    result.moved += 1
                } else {
                    result.skipped += 1
                }
            }
        }

        return result
    }

    /// Match strategy: prefer exact title; otherwise, if the app exposes only one window, take it;
    /// otherwise skip. Predictable beats clever for this version.
    private static func matchIndex(for snapshot: WindowSnapshot,
                                   in windows: [AXUIElement]) -> Int? {
        if !snapshot.title.isEmpty,
           let idx = windows.firstIndex(where: { AX.string($0, kAXTitleAttribute) == snapshot.title }) {
            return idx
        }
        if windows.count == 1 { return 0 }
        return nil
    }

    /// Layered fallback for placing a saved window on the currently-connected display set:
    ///
    /// 1. Same role available → proportional placement on that display.
    /// 2. Saved on External N, no display in slot N → try lower slots in descending order.
    /// 3. No external slot satisfies → fall onto built-in if available.
    /// 4. Saved on built-in, no built-in available (rare clamshell case) → first display.
    /// 5. No usable role/normalization info → use absolute frame, clamped on-screen.
    private static func computeTargetFrame(for snapshot: WindowSnapshot,
                                           currentDisplays: [Display]) -> CGRect {
        if let role = snapshot.displayRole, let normalized = snapshot.normalizedFrame {
            if let exact = currentDisplays.first(where: { $0.role == role }) {
                return denormalize(normalized, in: exact.frame)
            }
            switch role {
            case .external(let slot):
                // Try lower-numbered externals
                for trySlot in stride(from: slot - 1, through: 1, by: -1) {
                    if let target = currentDisplays.first(where: { $0.role == .external(slot: trySlot) }) {
                        return denormalize(normalized, in: target.frame)
                    }
                }
                // Then built-in
                if let builtIn = currentDisplays.first(where: { $0.role == .builtIn }) {
                    return denormalize(normalized, in: builtIn.frame)
                }
                // Then anything connected
                if let anyDisplay = currentDisplays.first {
                    return denormalize(normalized, in: anyDisplay.frame)
                }
            case .builtIn:
                // Built-in disappeared: fall onto the first available external.
                if let anyDisplay = currentDisplays.first {
                    return denormalize(normalized, in: anyDisplay.frame)
                }
            }
        }
        return clampedAbsolute(snapshot.absoluteFrame)
    }

    private static func denormalize(_ norm: NormalizedFrame, in displayFrame: CGRect) -> CGRect {
        CGRect(
            x: displayFrame.minX + norm.x * displayFrame.width,
            y: displayFrame.minY + norm.y * displayFrame.height,
            width: norm.width * displayFrame.width,
            height: norm.height * displayFrame.height
        )
    }

    private static func clampedAbsolute(_ frame: CGRect) -> CGRect {
        let union = Geometry.unionOfAllScreens()
        if union.intersects(frame) { return frame }

        guard let main = NSScreen.screens.first else { return frame }
        let mainRect = Geometry.topLeftFrame(of: main)
        let w = min(frame.width, mainRect.width)
        let h = min(frame.height, mainRect.height)
        return CGRect(x: mainRect.midX - w / 2,
                      y: mainRect.midY - h / 2,
                      width: w,
                      height: h)
    }
}
