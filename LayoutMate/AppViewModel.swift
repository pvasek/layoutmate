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

    /// Per-display "(role, currentSpaceID?)" so the menu can tell the user which Space
    /// Save/Restore would operate on right now. `nil` spaceID means the private read
    /// API didn't return a value for that display.
    @Published private(set) var currentSpaceByRole: [DisplayRole: UInt64?] = [:]

    /// Set while a Save/Restore walk is in progress, so the menu can disable both buttons
    /// (otherwise re-clicks would race with the Space-switching animation).
    @Published private(set) var isWorking: Bool = false

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

    /// One click of Save walks every Space on every connected display, capturing windows
    /// on each. Always ends back on the Space the user was on, with the originally-focused
    /// app re-activated, regardless of how the walk went.
    func saveLayout() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { self.isWorking = false }
            await self.runSaveAcrossAllSpaces()
        }
    }

    func restoreLayout() {
        guard !isWorking else { return }
        guard data.layout != nil else {
            lastAction = "No saved layout"
            return
        }
        isWorking = true
        Task { @MainActor in
            defer { self.isWorking = false }
            await self.runRestoreAcrossAllSpaces()
        }
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

    // MARK: - Save / restore walks

    private typealias OriginalSpace = (uuid: String, spaceID: SpaceDiscovery.SpaceID)

    private func runSaveAcrossAllSpaces() async {
        let cgIDs = displays.compactMap { $0.cgDisplayID }
        let displaySpaces = SpaceDiscovery.enumerate(displayIDs: cgIDs)

        // Fallback when the private API isn't usable.
        guard !displaySpaces.isEmpty else {
            do {
                let fresh = try WindowCapture.capture(displays: displays)
                data.layout = fresh
                try LayoutStore.save(data)
                hasSavedLayout = true
                savedAt = fresh.savedAt
                let n = fresh.windows.count
                lastAction = "Saved \(n) window\(n == 1 ? "" : "s") (current Space only — Space API unavailable)"
            } catch {
                lastAction = "Save failed: \(error.localizedDescription)"
            }
            return
        }

        // Snapshot the pre-walk state ONCE. Everything else flows from these so even if the
        // walk goes sideways we can put the user exactly back where they started.
        let originalSpaces: [OriginalSpace] = displaySpaces.map { ($0.displayUUID, $0.currentSpaceID) }
        let originallyFrontmost = NSWorkspace.shared.frontmostApplication

        let totalSpaces = displaySpaces.reduce(0) { $0 + $1.allSpaceIDs.count }
        var collected: [WindowSnapshot] = []
        var captureError: Error?
        var visited = 0

        walking: for ds in displaySpaces {
            guard let display = displays.first(where: { $0.cgDisplayID == ds.displayID }) else { continue }

            for spaceID in ds.allSpaceIDs {
                if spaceID != ds.currentSpaceID {
                    SpaceDiscovery.setCurrentSpace(spaceID, on: ds.displayUUID)
                    try? await Task.sleep(nanoseconds: spaceSwitchDelayNs)
                }

                visited += 1
                lastAction = "Capturing… \(visited)/\(totalSpaces) Spaces"

                do {
                    let fresh = try WindowCapture.capture(displays: displays)
                    let mine = fresh.windows.filter { $0.displayRole == display.role }
                    let tagged = mine.map { snap in
                        WindowSnapshot(
                            bundleId: snap.bundleId,
                            appName: snap.appName,
                            title: snap.title,
                            displayRole: snap.displayRole,
                            spaceID: spaceID,
                            normalizedFrame: snap.normalizedFrame,
                            absoluteFrame: snap.absoluteFrame
                        )
                    }
                    collected.append(contentsOf: tagged)
                } catch {
                    captureError = error
                    break walking
                }
            }
        }

        // Single deterministic return-to-original at the very end. Runs even on error.
        await returnToOriginals(originalSpaces, frontmost: originallyFrontmost)

        if let error = captureError {
            lastAction = "Save failed: \(error.localizedDescription)"
            return
        }

        let merged = Layout(savedAt: Date(), windows: collected)
        data.layout = merged
        do {
            try LayoutStore.save(data)
            hasSavedLayout = true
            savedAt = merged.savedAt
            lastAction = "Saved \(collected.count) windows across \(totalSpaces) Space\(totalSpaces == 1 ? "" : "s")"
        } catch {
            lastAction = "Save failed: \(error.localizedDescription)"
        }
    }

    private func runRestoreAcrossAllSpaces() async {
        guard let layout = data.layout else { return }

        let cgIDs = displays.compactMap { $0.cgDisplayID }
        let displaySpaces = SpaceDiscovery.enumerate(displayIDs: cgIDs)

        guard !displaySpaces.isEmpty else {
            let result = WindowRestorer.restore(layout, currentDisplays: displays)
            let skipped = result.skipped > 0 ? " (skipped \(result.skipped))" : ""
            lastAction = "Restored \(result.moved)/\(result.attempted)\(skipped) (current Space only — Space API unavailable)"
            return
        }

        let originalSpaces: [OriginalSpace] = displaySpaces.map { ($0.displayUUID, $0.currentSpaceID) }
        let originallyFrontmost = NSWorkspace.shared.frontmostApplication

        var totalMoved = 0
        var totalSkipped = 0

        for ds in displaySpaces {
            guard let display = displays.first(where: { $0.cgDisplayID == ds.displayID }) else { continue }

            // Visit only the Spaces that actually have saved windows for this role.
            let neededSpaces = Set(layout.windows
                .filter { $0.displayRole == display.role }
                .compactMap { $0.spaceID })
            let toVisit = ds.allSpaceIDs.filter { neededSpaces.contains($0) }
            guard !toVisit.isEmpty else { continue }

            for spaceID in toVisit {
                if spaceID != ds.currentSpaceID {
                    SpaceDiscovery.setCurrentSpace(spaceID, on: ds.displayUUID)
                    try? await Task.sleep(nanoseconds: spaceSwitchDelayNs)
                }
                lastAction = "Restoring… \(display.role.displayLabel) Space"
                let result = WindowRestorer.restore(layout, currentDisplays: displays)
                totalMoved += result.moved
                totalSkipped += result.skipped
            }
        }

        await returnToOriginals(originalSpaces, frontmost: originallyFrontmost)

        let skipped = totalSkipped > 0 ? " (skipped \(totalSkipped))" : ""
        lastAction = "Restored \(totalMoved) windows\(skipped)"
    }

    /// Switches every display back to the Space it was on when the user clicked, then
    /// re-activates the originally-frontmost app so the focused window lands where it was.
    /// Generous wait at the end so animations finish before we return control.
    ///
    /// `tickleWindowServer` runs in the middle: programmatic Space switching via the
    /// private CGS API logically changes which Space is foregrounded, but the wallpaper
    /// and Dock layer often don't redraw until something nudges the window server.
    /// A 1-pixel cursor jiggle is the standard workaround — invisible to the user, but
    /// it prods the system to refresh the visible Space.
    private func returnToOriginals(_ originals: [OriginalSpace], frontmost: NSRunningApplication?) async {
        for (uuid, spaceID) in originals {
            SpaceDiscovery.setCurrentSpace(spaceID, on: uuid)
        }
        try? await Task.sleep(nanoseconds: returnSettleNs)
        tickleWindowServer()
        // Re-activate AFTER the Space switches have settled, so activate doesn't drag
        // macOS into a different Space to find the app's window.
        frontmost?.activate()
    }

    /// Forces the window server to redraw by warping the cursor 1 pixel and back. This
    /// addresses a known glitch where `CGSManagedDisplaySetCurrentSpace` switches the
    /// logical Space without triggering a full visual refresh — leaving the wallpaper
    /// and chrome from the previously-visible Space painted on screen.
    private func tickleWindowServer() {
        let cocoa = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cg = CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)
        CGWarpMouseCursorPosition(CGPoint(x: cg.x + 1, y: cg.y))
        CGWarpMouseCursorPosition(cg)
    }

    /// macOS's Space-switch animation runs ~500 ms; this is the wait between switching and
    /// reading the new state during the walk.
    private let spaceSwitchDelayNs: UInt64 = 600_000_000

    /// Final settle wait at the end of the walk — slightly longer because every display is
    /// being switched at once and we want all the animations to be done before we declare
    /// the user is "back home."
    private let returnSettleNs: UInt64 = 1_000_000_000

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

        var nextSpaceMap: [DisplayRole: UInt64?] = [:]
        for display in classified {
            let cgID = display.cgDisplayID
            nextSpaceMap[display.role] = cgID.flatMap(SpaceDiscovery.currentSpaceID(for:))
        }
        currentSpaceByRole = nextSpaceMap
    }
}
