import AppKit
import ApplicationServices
import Combine

/// Watches the system Accessibility-permission state for this app and exposes it as `@Published`.
/// Polls every 2 seconds so the menu reflects the user toggling the switch in System Settings.
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            DispatchQueue.main.async { [weak self] in
                self?.isTrusted = trusted
            }
        }
    }

    /// Triggers the system prompt (registers the app in the Accessibility list)
    /// and deep-links to the Privacy → Accessibility pane in System Settings.
    func requestAndOpenSettings() {
        let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
