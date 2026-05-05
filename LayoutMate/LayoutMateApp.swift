import SwiftUI

@main
struct LayoutMateApp: App {
    var body: some Scene {
        MenuBarExtra("LayoutMate", systemImage: "macwindow.on.rectangle") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)
    }
}
