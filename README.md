# LayoutMate

A macOS menu-bar app that saves your window arrangement and restores it across different display setups.

One saved layout adapts to whatever displays are currently connected. Each window remembers the role of its host display — built-in, or a user-assigned External 1, 2, … — plus its proportional position within that display. So the same saved layout works at the office, at home, on the road, with whatever monitors you plug in.

## Build

Requires Xcode 15+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make build       # build Debug
make run         # build and launch
make help        # see all targets
```

On first **Save** or **Restore**, LayoutMate will ask for Accessibility permission — required so it can read and move other apps' windows.

## How it works

- **Save layout** captures every visible window's app, title, host-display role, and proportional frame.
- **Restore layout** matches each saved window to a live window of the same app, then places it on the display currently holding the same role (or folds onto a lower role / built-in if the original role isn't connected).
- When 2+ externals are connected, each gets a small submenu in the menu bar to pick its slot — assignments stick to the physical hardware.
- Storage: `~/Library/Application Support/LayoutMate/store.json`.

See [`SPEC.md`](SPEC.md) for the full behavior spec and [`TECH.md`](TECH.md) for implementation notes.

## License

[MIT](LICENSE).
