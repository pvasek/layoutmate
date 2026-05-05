# macscreen — Technical Approach (v1)

A short map from the spec to the code we're about to write. Not a tutorial — just the decisions.

## Stack

- **Language:** Swift 5.9+
- **UI shell:** SwiftUI, using `MenuBarExtra` for the status bar icon and menu
- **Window manipulation:** AppKit + Accessibility framework (no SwiftUI equivalent exists)
- **Build:** Xcode 15+, single app target
- **Minimum macOS:** 13 (Ventura) — required by `MenuBarExtra` and `SMAppService`; comfortably old by 2026
- **Distribution:** signed with Developer ID, notarized, distributed directly. **Not App Store** — the sandbox forbids the Accessibility access we need to move other apps' windows.

### Why Swift native (and not Electron / Tauri)

The two non-trivial APIs are macOS-only C/Objective-C: `AXUIElement` for moving windows, IOKit for display identity. Any cross-platform shell would still need a native helper, so we'd pay the cross-platform cost without the benefit.

### Concept bridges from your background

- **SwiftUI** ≈ XAML+MVVM, but views are Swift code, not a separate `.xaml` file. `@State` / `@Binding` is `INotifyPropertyChanged` wired up automatically.
- **AppKit** ≈ WinForms-era imperative Cocoa; still alive underneath SwiftUI, used when SwiftUI doesn't cover something.
- **Codable** ≈ `System.Text.Json` with attributes, but built into the language.
- **Accessibility framework** is the one place that still feels like 2005-era Carbon C. We'll write thin Swift wrappers around it once and not touch them again.

## API map

| Need | API |
|---|---|
| Menu bar icon + dropdown | `MenuBarExtra` (SwiftUI, macOS 13+) |
| List running apps | `NSWorkspace.shared.runningApplications` |
| Enumerate visible windows (fast, read-only) | `CGWindowListCopyWindowInfo` |
| Read & move any app's window | `AXUIElement` + `kAXPositionAttribute`, `kAXSizeAttribute` |
| Check / request Accessibility permission | `AXIsProcessTrustedWithOptions` |
| List physical screens | `NSScreen.screens` |
| Persist saved layout | JSON file in `~/Library/Application Support/macscreen/` |
| Launch at login | `SMAppService.mainApp` (macOS 13+) |

For v2 — display identity via `CGDirectDisplayID` + `IODisplayCreateInfoDictionary` (vendor / model / serial). Out of scope for v1, flagged so we don't paint ourselves into a corner.

## Project layout

Flat, small. No premature folders.

```
macscreen/
  macscreen.xcodeproj
  macscreen/
    macscreenApp.swift            # @main, MenuBarExtra
    MenuContent.swift             # the dropdown UI
    WindowSnapshot.swift          # Codable: app bundle id, title, frame, screen index
    Layout.swift                  # collection of WindowSnapshots + metadata
    LayoutStore.swift             # load / save JSON
    WindowCapture.swift           # read all visible windows via AX
    WindowRestorer.swift          # apply a Layout via AX
    AccessibilityPermission.swift # check + prompt + deep-link
  SPEC.md
  TECH.md
```

## The honest hard parts

1. **`AXUIElement` is C.** Reading and writing window position/size needs `AXUIElementCopyAttributeValue` / `AXUIElementSetAttributeValue` with `CFTypeRef` boxing. It's bounded — ~100 lines of bridging code, written once.
2. **Window matching is heuristic.** "The window I saved" and "the window now" are linked by app bundle id + title. Browser tabs and document apps change titles freely. v1 strategy: match by bundle id + exact title; fall back to "the only window of this app" if there's exactly one; otherwise skip. Not clever, but predictable.
3. **Permissions UX.** macOS Accessibility permission must be toggled by the user in System Settings — we can't grant it programmatically. We can deep-link to the right pane and detect when it flips on. Build this into first-run, not as an afterthought.

## Build order

Each step is independently testable.

1. **Menu bar shell** — icon shows, menu opens, items disabled. ~30 min.
2. **Accessibility permission flow** — detect, prompt, deep-link, re-check.
3. **Capture** — log every visible window's app / title / frame to console on demand. No saving yet.
4. **Persistence** — wrap the snapshot in a `Layout`, write JSON, read it back.
5. **Restore** — apply a saved `Layout`. First end-to-end loop.
6. **Polish** — success indicator, "no permission" tooltip, launch-at-login toggle.

Step 5 is when the app first feels real. Steps 1–4 are plumbing.
