import SwiftUI
import AppKit

struct MenuContent: View {
    @StateObject private var permission = AccessibilityPermission()
    @StateObject private var vm = AppViewModel()

    var body: some View {
        if permission.isTrusted {
            connectedDisplaysSection
            Divider()
            actionsSection
            Divider()
            if let lastAction = vm.lastAction {
                Text(lastAction)
            }
            Button("About macscreen") { showAbout() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        } else {
            Text("Accessibility permission required")
            Button("Open Accessibility settings…") { permission.requestAndOpenSettings() }
            Button("Re-check permission") { permission.refresh() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectedDisplaysSection: some View {
        if vm.displays.isEmpty {
            Text("No displays detected")
        } else {
            Text("Connected:")
            ForEach(vm.displays, id: \.identity.fingerprint) { display in
                displayRow(display)
            }
        }
    }

    @ViewBuilder
    private func displayRow(_ display: Display) -> some View {
        let label = "\(display.localizedName) — \(display.role.displayLabel)"
        if display.isBuiltIn || vm.totalKnownSlots < 2 {
            Text(label)
        } else {
            Menu(label) {
                ForEach(1...vm.totalKnownSlots, id: \.self) { slot in
                    let isCurrent = display.role == .external(slot: slot)
                    Button("External \(slot)\(isCurrent ? "  (current)" : "")") {
                        vm.assignSlot(slot, toExternalWithIdentity: display.identity)
                    }
                    .disabled(isCurrent)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Button("Save layout") { vm.saveLayout() }
        Button(restoreButtonTitle) { vm.restoreLayout() }
            .disabled(!vm.hasSavedLayout)
    }

    private var restoreButtonTitle: String {
        if let savedAt = vm.savedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Restore layout (saved \(formatter.string(from: savedAt)))"
        }
        return "Restore layout"
    }

    // MARK: - Helpers

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
