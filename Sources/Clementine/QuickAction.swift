import AppKit

enum QuickActionError: LocalizedError {
    case airDropUnavailable

    var errorDescription: String? {
        switch self {
        case .airDropUnavailable: "AirDrop is turned off or can't send these files."
        }
    }
}

enum QuickAction: CaseIterable {
    case copyPath
    case airDrop

    var title: String {
        switch self {
        case .copyPath: "Copy Path"
        case .airDrop: "AirDrop"
        }
    }

    var symbol: String {
        switch self {
        case .copyPath: "doc.on.clipboard"
        case .airDrop: "dot.radiowaves.left.and.right"
        }
    }

    @MainActor
    func perform(on files: [URL]) async throws {
        assert(!files.isEmpty)
        switch self {
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(files.map(\.path).joined(separator: "\n"), forType: .string)

        case .airDrop:
            guard
                let service = NSSharingService(named: .sendViaAirDrop),
                service.canPerform(withItems: files)
            else { throw QuickActionError.airDropUnavailable }
            // The picker opens behind the frontmost app unless this menu-bar app activates first.
            NSApp.activate()
            service.perform(withItems: files)
        }
    }
}
