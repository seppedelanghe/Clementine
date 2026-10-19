import Sparkle
import SwiftUI
import os

@main
struct ClementineApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    // Loaded from the bundle because asset catalogs need Xcode's actool to compile.
    private static let menuBarIcon: NSImage = {
        guard
            let url = Bundle.main.url(forResource: "clementine-menubar", withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else { preconditionFailure("The menu bar icon is missing from the app bundle") }
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        let activity = appDelegate.activity
        let loginItem = appDelegate.loginItem
        MenuBarExtra {
            ForEach(activity.visibleJobs) { job in
                Text(Self.describe(job))
            }
            if !activity.visibleJobs.isEmpty {
                Divider()
            }
            Toggle("Launch at Login", isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))
            if loginItem.needsApproval {
                Button("Allow in Login Items…") { loginItem.openSystemSettings() }
            }
            Button("Check for Updates…") { appDelegate.updater.checkForUpdates(nil) }
            SettingsButton()
            Divider()
            Button("Quit Clementine") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.menuBarIcon)
                if let fraction = activity.fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                }
            }
        }
        Settings {
            SettingsView(loginItem: loginItem)
        }
    }

    // "clip.mkv → MP4 (2 of 3) · 42%"
    private static func describe(_ job: ConversionActivity.Job) -> String {
        let file = job.files[job.fileIndex].lastPathComponent
        let count = job.files.count > 1 ? " (\(job.fileIndex + 1) of \(job.files.count))" : ""
        let percent = job.fraction.formatted(.percent.precision(.fractionLength(0)))
        return "\(file) → \(job.format.title)\(count) · \(percent)"
    }
}

private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            // A menu bar app isn't active, so its windows would open behind the frontmost app.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let activity = ConversionActivity()
    let loginItem = LoginItem()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private let logger = Logger(subsystem: "be.seppedelanghe.clementine", category: "wheel")
    private let registry = ConverterRegistry(converters: [
        ImageConverter(), VideoConverter(), AudioConverter(), FFmpegVideoConverter(), FFmpegAudioConverter(),
        ArchiveConverter(), FolderConverter(), DocxConverter(), MarkdownConverter(), TextDocumentConverter(),
        PDFTextConverter(),
    ])
    private var dragMonitor: DragMonitor?
    private var wheelController: WheelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runner = ConversionRunner(registry: registry)
        let wheel = WheelController { [logger, activity] item, files in
            switch item.action {
            case .convert(let format):
                Task {
                    let job = activity.begin(files, to: format)
                    let failures = await runner.run(files, to: format) { fileIndex, fraction in
                        Task { @MainActor in activity.update(job, fileIndex: fileIndex, fileFraction: fraction) }
                    }
                    activity.end(job)
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
            case .quickAction(let action):
                Task {
                    do {
                        try await action.perform(on: files)
                    } catch {
                        logger.error("\(action.title, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                        do {
                            try await FailureNotification.post(error, for: action)
                        } catch {
                            logger.error("Failure notification not posted: \(String(describing: error), privacy: .public)")
                        }
                    }
                }
            }
        }
        let monitor = DragMonitor(
            bindings: { Dictionary(uniqueKeysWithValues: Wheel.allCases.map { ($0, $0.modifier.flags) }) },
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
                QuickAction.allCases
                    .filter { $0.isAvailable(for: trigger.files) }
                    .map { WheelItem(title: $0.title, symbol: $0.symbol, action: .quickAction($0)) }
            )
        }
    }
}
