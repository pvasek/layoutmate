# LayoutMate — Behavior Specification

A macOS menu-bar app that remembers where your windows were and puts them back.

## Why this exists

When you change displays — plug in a different external monitor, dock at a different desk, switch from HDMI to USB-C — macOS loses track of where your windows belong. Every app ends up dumped onto whichever screen survives, and you spend the next ten minutes dragging things back into place.

LayoutMate lets you snapshot a window arrangement once, then restore it with a single click.

---

## v1 — The minimum viable app

The whole point of v1 is to prove the core loop is useful before building anything clever. Two commands. One stored layout. No monitor awareness.

### What the user sees

- A small icon in the menu bar (top-right, near the clock).
- Clicking the icon opens a menu with two items:
  - **Save current layout**
  - **Restore layout**
- A third item, **Quit**, and a small **About / Permissions** entry.

### What "Save current layout" does

Captures the current arrangement of every visible window across all running applications:

- Which application owns the window (e.g. *Safari*, *Visual Studio Code*).
- A label that helps identify the window later (typically the window title).
- The window's position and size on screen.
- Which physical screen it's on, when there are multiple.

Saving overwrites the previous saved layout. There is only ever one slot in v1.

The menu bar icon briefly indicates success (e.g. a checkmark flash). No dialog appears unless something went wrong.

### What "Restore layout" does

For each window in the saved layout, LayoutMate tries to put a matching window back where it was:

- If the application is **running and has a matching window** → move and resize it.
- If the application is **running but no matching window is open** → skip it. (v1 does not open documents or new windows.)
- If the application is **not running** → skip it. (v1 does not launch apps.)

"Matching" in v1 is best-effort: same application, and same window title if possible. If multiple windows could match, LayoutMate picks one and moves on rather than asking.

If a saved window's screen no longer exists (e.g. the external monitor is unplugged), the window is placed on the main screen at the closest equivalent position that's actually visible.

### First-run experience

The first time the user clicks **Save** or **Restore**, macOS will need permission to read and move other applications' windows (Accessibility permission). LayoutMate:

1. Explains in plain language why the permission is needed.
2. Opens the relevant System Settings pane for the user.
3. Detects when permission is granted and continues without requiring a relaunch.

Until permission is granted, **Save** and **Restore** are visible but disabled, with a tooltip explaining why.

### Login behavior

LayoutMate launches at login by default (toggleable in a small preferences area). It does **not** auto-restore on launch in v1 — restoring is always a deliberate user action.

### What v1 does *not* do

Listed explicitly so we don't confuse ourselves later:

- No multiple named layouts.
- No monitor-set awareness — saving on one display setup and restoring on another will produce a best-effort result, not a smart one.
- No proportional remapping across different screen sizes.
- No automatic restore when displays change.
- No launching of apps that aren't running.
- No reopening of specific documents or tabs.
- No keyboard shortcuts (can be added trivially later).
- No iCloud sync; the layout is local to this Mac.

---

## v2 — The interesting version

The version that motivated the whole project. Built on v1's foundation.

The crucial observation: there is still **only ever one saved layout**. Different physical setups don't get separate layouts — the *same* layout adapts to whatever displays are currently plugged in.

### Display roles, not display identities

Each connected display is classified into a role:

- **Built-in** — automatically detected (the laptop's own screen).
- **External 1, External 2, …** — every external monitor gets a numbered slot. The first time a new external is seen, it auto-receives the next free slot. The user can swap which monitor holds which slot from the menu.

These slot assignments are **persistent per physical display** (keyed by the monitor's hardware identity from EDID, so unplug/replug/reboot doesn't lose them). They are *not* per-location — the user simply assigns slots once at each location, and the assignments stick to the physical hardware.

The point of slots: at the office, the user says "the Dell on my left is External 1, the Dell on my right is External 2". At home, the user says "the LG is External 1, the Samsung is External 2". LayoutMate now knows which "1" and which "2" the user means in each place, and can place the same saved layout correctly in both.

### Proportional capture and restore

Each saved window remembers two things:

- **The role of the display it was on** (built-in, or external N).
- **Its position and size as a proportion of that display** — e.g. "right half, top quarter, 40% × 60% of the display".

This makes the same layout work across different-resolution monitors. A window on the right half of a 4K External 1 restores to the right half of a 1080p External 1.

### Restore: layered fallback

When restoring, each window is placed in the first matching slot found:

1. **Same role available** → place proportionally on that display.
2. **Lower-numbered external slot available** (e.g. saved on External 2, only External 1 connected) → fall down to the lower slot.
3. **Built-in available** (e.g. saved on an external, no externals connected) → fall onto built-in.
4. **No display info** or above all fail → use the saved absolute frame, clamped to whatever's visible.

The layered fold-down means windows always end up *somewhere visible*, even on hardware setups that don't fully match what was saved.

### What the menu shows

- A list of currently-connected displays with their assigned roles ("Dell U2723QE — External 1").
- **Save layout** — captures the current arrangement.
- **Restore layout** — applies the saved layout to whatever's connected now.
- **Per-external slot reassignment** — when 2+ slots are known (currently connected or remembered), each external gets a small submenu to pick its slot. Picking a slot already held by another external swaps them.

### Automatic restore on display change (opt-in)

When LayoutMate detects that the connected display set has changed, it offers — or, if the user opted in, automatically performs — a restore. (Lower priority than the above; the manual Restore is the foundation.)

---

## Non-goals (probably ever)

- Tiling / window-snapping (Rectangle, Magnet already do this well).
- Cross-machine sync of layouts (different machine = different apps installed = mismatch hell).
- Scripting or automation API.
