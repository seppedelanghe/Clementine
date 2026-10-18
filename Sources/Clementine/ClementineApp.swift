import SwiftUI
import os

@main
struct ClementineApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Clementine", systemImage: "arrow.triangle.2.circlepath") {
            Button("Quit Clementine") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "be.seppedelanghe.clementine", category: "drag")
    private var dragMonitor: DragMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = DragMonitor(bindings: [.convert: .shift, .actions: .control]) { [logger] trigger in
            let files = trigger.files.map(\.path).joined(separator: ", ")
            logger.notice(
                "\(String(describing: trigger.wheel), privacy: .public) at (\(trigger.location.x), \(trigger.location.y)): \(files, privacy: .public)"
            )
        }
        monitor.start()
        dragMonitor = monitor
    }
}
