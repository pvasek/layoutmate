import AppKit
import Combine
import Foundation

/// View model for the menu UI. Owns the persisted store, the classified-display list, and
/// the current "last action" message. Reacts to display changes (plug/unplug/rearrange) via
/// NSApplication's screen-parameters notification.
@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var hasSavedLayout: Bool = false
    @Published private(set) var savedAt: Date?
    @Published var lastAction: String?

    /// Number of slots the menu's reassignment submenus should offer per external. Equal to
    /// max(connected externals, total known slots). When < 2 the menu omits the submenu.
    @Published private(set) var totalKnownSlots: Int = 0

    private var data: StoreData = LayoutStore.load()
    private var observer: NSObjectProtocol?

    init() {
        refreshFromCurrentDisplays()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromCurrentDisplays()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - User actions

    func saveLayout() {
        do {
            let layout = try WindowCapture.capture(displays: displays)
            data.layout = layout
            try LayoutStore.save(data)
            hasSavedLayout = true
            savedAt = layout.savedAt
            let count = layout.windows.count
            lastAction = "Saved \(count) window\(count == 1 ? "" : "s")"
        } catch {
            lastAction = "Save failed: \(error.localizedDescription)"
        }
    }

    func restoreLayout() {
        guard let layout = data.layout else {
            lastAction = "No saved layout"
            return
        }
        let result = WindowRestorer.restore(layout, currentDisplays: displays)
        let skipped = result.skipped > 0 ? " (skipped \(result.skipped))" : ""
        lastAction = "Restored \(result.moved)/\(result.attempted)\(skipped)"
    }

    /// Assign `newSlot` to the external display identified by `identity`. If another known
    /// display currently holds `newSlot`, it gets the displaced display's old slot in return
    /// — i.e. this is a swap, not a clobber.
    func assignSlot(_ newSlot: Int, toExternalWithIdentity identity: DisplayIdentity) {
        let fp = identity.fingerprint
        let oldSlot = data.displayRoles[fp]

        if let conflictingFP = data.displayRoles.first(where: { $0.value == newSlot && $0.key != fp })?.key {
            if let oldSlot {
                data.displayRoles[conflictingFP] = oldSlot
            } else {
                // The display being assigned a slot didn't have one yet (shouldn't happen for
                // an external that's been classified, but defensive). Give the displaced one
                // the next free slot.
                let used = Set(data.displayRoles.values).subtracting([newSlot])
                data.displayRoles[conflictingFP] = (used.max() ?? 0) + 1
            }
        }
        data.displayRoles[fp] = newSlot
        try? LayoutStore.save(data)
        refreshFromCurrentDisplays()
    }

    // MARK: - Internals

    private func refreshFromCurrentDisplays() {
        let raws = DisplayDiscovery.currentDisplays()
        let (classified, updatedRoles) = DisplayDiscovery.classify(raws, roles: data.displayRoles)

        if updatedRoles != data.displayRoles {
            data.displayRoles = updatedRoles
            try? LayoutStore.save(data)
        }

        displays = classified
        hasSavedLayout = data.layout != nil
        savedAt = data.layout?.savedAt
        let connectedExternals = classified.filter { !$0.isBuiltIn }.count
        let knownSlots = data.displayRoles.values.max() ?? 0
        totalKnownSlots = max(connectedExternals, knownSlots)
    }
}
