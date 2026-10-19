import AppKit
import UniformTypeIdentifiers

enum QuickActionError: LocalizedError {
    case airDropUnavailable
    case copyFailed
    case folderAccessDenied(String)

    var errorDescription: String? {
        switch self {
        case .airDropUnavailable: "AirDrop is turned off or can't send these files."
        case .copyFailed: "The files could not be copied."
        case .folderAccessDenied(let folder):
            "Clementine can't access \(folder). Allow it in System Settings under Privacy & Security, Files & Folders."
        }
    }
}

enum QuickAction: CaseIterable {
    case copy
    case copyPath
    case airDrop
    case extract

    var title: String {
        switch self {
        case .copy: "Copy"
        case .copyPath: "Copy Path"
        case .airDrop: "AirDrop"
        case .extract: "Extract"
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .copyPath: "doc.on.clipboard"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .extract: "archivebox"
        }
    }

    func isAvailable(for files: [URL]) -> Bool {
        switch self {
        case .copy, .copyPath, .airDrop: true
        case .extract:
            files.allSatisfy { file in
                guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
                return ArchiveConverter.readableTypes.contains(where: type.conforms(to:))
            }
        }
    }

    @MainActor
    func perform(on files: [URL]) async throws {
        assert(!files.isEmpty)
        switch self {
        case .copy:
            // File URLs on the pasteboard are what Finder's own Copy writes, so pasting in Finder
            // duplicates the files and pasting into Mail or a chat attaches them.
            try await Self.requestFolderAccess(for: files)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects(files as [NSURL]) else { throw QuickActionError.copyFailed }

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

        case .extract:
            for archive in files {
                try await Self.extract(archive)
            }
        }
    }

    // Like Archive Utility: a single top-level item lands beside the archive as it is, anything
    // more goes into a folder named after the archive.
    private static func extract(_ archive: URL) async throws {
        let directory = archive.deletingLastPathComponent()
        let workspace = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: directory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        let contents = workspace.appending(path: "contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
        // Zips made by Finder carry resource forks in __MACOSX; Archive Utility hides it too.
        try await BSDTar.run(["-x", "-f", archive.path, "-C", contents.path, "--exclude", "__MACOSX"])

        let items = try FileManager.default.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil)
        if items.count == 1 {
            let item = items[0]
            let name = item.lastPathComponent
            let base = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                ? name
                : FileManager.baseName(of: name)
            let destination = FileManager.default.availableURL(
                base: base,
                suffix: String(name.dropFirst(base.count)),
                in: directory
            )
            try FileManager.default.moveItem(at: item, to: destination)
        } else {
            let destination = FileManager.default.availableURL(
                base: FileManager.baseName(of: archive.lastPathComponent),
                suffix: "",
                in: directory
            )
            try FileManager.default.moveItem(at: contents, to: destination)
        }
    }

    // The pasteboard silently drops a file unless Clementine can read its folder, even though
    // writeObjects reports success. For Desktop, Documents and Downloads macOS only asks for
    // that access once the folder is actually listed.
    private static func requestFolderAccess(for files: [URL]) async throws {
        for folder in Set(files.map { $0.deletingLastPathComponent().path }) {
            do {
                // Off the main actor: the call blocks until the user answers the privacy prompt.
                _ = try await Task.detached { try FileManager.default.contentsOfDirectory(atPath: folder) }.value
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                throw QuickActionError.folderAccessDenied(FileManager.default.displayName(atPath: folder))
            }
        }
    }
}
