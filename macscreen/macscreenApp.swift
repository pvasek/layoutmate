import SwiftUI

@main
struct MacscreenApp: App {
    var body: some Scene {
        MenuBarExtra("macscreen", systemImage: "macwindow.on.rectangle") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)
    }
}
