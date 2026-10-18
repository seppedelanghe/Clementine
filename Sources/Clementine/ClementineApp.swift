import SwiftUI

@main
struct ClementineApp: App {
    var body: some Scene {
        MenuBarExtra("Clementine", systemImage: "arrow.triangle.2.circlepath") {
            Button("Quit Clementine") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
