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
    case compress
    case extract

    var title: String {
        switch self {
        case .copy: "Copy"
        case .copyPath: "Copy Path"
        case .airDrop: "AirDrop"
        case .compress: "Compress"
        case .extract: "Extract"
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .copyPath: "doc.on.clipboard"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .compress: "doc.zipper"
        case .extract: "archivebox"
        }
    }

    func isAvailable(for files: [URL]) -> Bool {
        switch self {
        case .copy, .copyPath, .airDrop: true
        // Archives are already compressed; a mix with other files can still be.
        case .compress: !files.allSatisfy(Self.isArchive)
        case .extract: files.allSatisfy(Self.isArchive)
        }
    }

    private static func isArchive(_ file: URL) -> Bool {
        guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return ArchiveConverter.readableTypes.contains(where: type.conforms(to:))
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

        case .compress:
            try await Self.compress(files)

        case .extract:
            for archive in files {
                try await Self.extract(archive)
            }
        }
    }

    // Like Compress in Finder: one item becomes "name.zip", keeping its extension, and several
    // become "Archive.zip" beside the first.
    private static func compress(_ items: [URL]) async throws {
        let directory = items[0].deletingLastPathComponent()
        let workspace = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: directory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        let temporary = workspace.appending(path: "archive.zip")
        // Each item is added from its own folder, so all of them sit at the archive's top level.
        let paths = items.flatMap { ["-C", $0.deletingLastPathComponent().path, $0.lastPathComponent] }
        try await BSDTar.run(["-c", "-f", temporary.path] + BSDTar.options(for: .zip) + BSDTar.fromDisk + paths)

        let destination = FileManager.default.availableURL(
            base: items.count == 1 ? items[0].lastPathComponent : "Archive",
            suffix: ".zip",
            in: directory
        )
        try FileManager.default.moveItem(at: temporary, to: destination)
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
            let base = try FileManager.baseName(of: item)
            let destination = FileManager.default.availableURL(
                base: base,
                suffix: String(name.dropFirst(base.count)),
                in: directory
            )
            try FileManager.default.moveItem(at: item, to: destination)
        } else {
            let destination = FileManager.default.availableURL(
                base: try FileManager.baseName(of: archive),
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
