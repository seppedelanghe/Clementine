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
    private let logger = Logger(subsystem: "be.seppedelanghe.clementine", category: "wheel")
    private var dragMonitor: DragMonitor?
    private var wheelController: WheelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wheel = WheelController { [logger] item, files in
            let paths = files.map(\.path).joined(separator: ", ")
            logger.notice("\(item.title, privacy: .public): \(paths, privacy: .public)")
        }
        let monitor = DragMonitor(
            bindings: [.convert: .shift, .actions: .control],
            onTrigger: { trigger in
                let (title, items) = Self.placeholderWheel(trigger.wheel)
                wheel.show(title: title, items: items, files: trigger.files, at: trigger.location)
            },
            onDragEnd: { wheel.dragEnded() }
        )
        monitor.start()
        dragMonitor = monitor
        wheelController = wheel
    }

    private static func placeholderWheel(_ wheel: Wheel) -> (String, [WheelItem]) {
        switch wheel {
        case .convert:
            ("Convert", ["JPG", "PNG", "HEIC", "TIFF", "PDF"].map { WheelItem(title: $0, symbol: "photo") })
        case .actions:
            (
                "Actions",
                [
                    WheelItem(title: "Copy Path", symbol: "doc.on.clipboard"),
                    WheelItem(title: "AirDrop", symbol: "dot.radiowaves.left.and.right"),
                    WheelItem(title: "Terminal", symbol: "terminal"),
                ]
            )
        }
    }
}
