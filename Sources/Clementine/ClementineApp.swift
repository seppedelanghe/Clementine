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
    private let registry = ConverterRegistry(converters: [ImageConverter()])
    private var dragMonitor: DragMonitor?
    private var wheelController: WheelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runner = ConversionRunner(registry: registry)
        let wheel = WheelController { [logger] item, files in
            switch item.action {
            case .convert(let format):
                Task {
                    let failures = await runner.run(files, to: format)
                    guard !failures.isEmpty else { return }
                    for failure in failures {
                        logger.error(
                            "\(failure.file.path, privacy: .public): \(String(describing: failure.error), privacy: .public)"
                        )
                    }
                    do {
                        try await FailureNotification.post(failures, to: format)
                    } catch {
                        logger.error("Failure notification not posted: \(String(describing: error), privacy: .public)")
                    }
                }
            case .placeholder:
                let paths = files.map(\.path).joined(separator: ", ")
                logger.notice("\(item.title, privacy: .public): \(paths, privacy: .public)")
            }
        }
        let monitor = DragMonitor(
            bindings: [.convert: .shift, .actions: .control],
            onTrigger: { [registry] trigger in
                let (title, items) = Self.wheelContent(for: trigger, registry: registry)
                // A wheel with nothing to offer would only block the ordinary drop underneath it.
                guard !items.isEmpty else { return }
                wheel.show(title: title, items: items, files: trigger.files, at: trigger.location)
            },
            onDragEnd: { wheel.dragEnded() }
        )
        monitor.start()
        dragMonitor = monitor
        wheelController = wheel
    }

    private static func wheelContent(
        for trigger: DragTrigger,
        registry: ConverterRegistry
    ) -> (String, [WheelItem]) {
        switch trigger.wheel {
        case .convert:
            (
                "Convert",
                registry.formats(for: trigger.files).map {
                    WheelItem(title: $0.title, symbol: $0.symbol, action: .convert($0))
                }
            )
        case .actions:
            (
                "Actions",
                [
                    WheelItem(title: "Copy Path", symbol: "doc.on.clipboard", action: .placeholder),
                    WheelItem(title: "AirDrop", symbol: "dot.radiowaves.left.and.right", action: .placeholder),
                    WheelItem(title: "Terminal", symbol: "terminal", action: .placeholder),
                ]
            )
        }
    }
}
