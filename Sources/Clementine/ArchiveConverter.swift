import Foundation
import UniformTypeIdentifiers

// bsdtar repacks in one pass: it reads the source's entries and writes them straight into the
// new archive, without extracting anything to disk.
struct ArchiveConverter: Converter {
    // Listed one by one because .archive also covers disk images and installer packages.
    // ".tar.gz" and ".tar.bz2" are typed as plain gzip and bzip2 by macOS.
    static let readableTypes: [UTType] = [
        .zip, .gzip, .bz2, .tar, .xz, .tarXz, .sevenZip, .rar,
    ]

    let inputs = readableTypes
    let outputs: [OutputFormat] = [.zip, .sevenZip, .tar, .tarGz, .tarXz]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        try await BSDTar.run(["-c", "-f", destination.path] + BSDTar.options(for: format) + ["@\(source.path)"])
    }
}

struct FolderConverter: Converter {
    // Not .directory, which includes apps and other packages.
    let inputs: [UTType] = [.folder]
    let outputs: [OutputFormat] = [.zip, .sevenZip, .tarGz, .tarXz]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        try await BSDTar.run(
            ["-c", "-f", destination.path] + BSDTar.options(for: format) + BSDTar.fromDisk
                + ["-C", source.deletingLastPathComponent().path, source.lastPathComponent]
        )
    }
}

private extension UTType {
    static let tar = UTType("public.tar-archive")!
    static let xz = UTType("org.tukaani.xz-archive")!
    static let tarXz = UTType("org.tukaani.tar-xz-archive")!
    static let sevenZip = UTType("org.7-zip.7-zip-archive")!
    static let rar = UTType(importedAs: "com.rarlab.rar-archive", conformingTo: .archive)
}

enum BSDTar {
    // Archives of files on disk are meant for any system, so they leave out what only a Mac uses.
    static let fromDisk = ["--no-mac-metadata", "--exclude", ".DS_Store"]

    static func options(for format: OutputFormat) -> [String] {
        switch format {
        case .zip: ["--format", "zip"]
        case .sevenZip: ["--format", "7zip"]
        // bsdtar's default, restricted pax, holds long names and large files and reads everywhere.
        case .tar: []
        case .tarGz: ["-z"]
        case .tarXz: ["-J"]
        default: preconditionFailure("No bsdtar options for \(format.title)")
        }
    }

    static func run(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        let exits = AsyncStream<Int32> { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }
        try process.run()

        // Drained while bsdtar runs: on an encrypted archive it prompts thousands of times.
        var errorLines: [String] = []
        for try await line in errors.fileHandleForReading.bytes.lines where errorLines.count < 50 {
            errorLines.append(line)
        }
        for await status in exits where status != 0 {
            throw error(from: errorLines)
        }
    }

    private static func error(from lines: [String]) -> ConversionError {
        // Without a terminal bsdtar can't ask for the password, so it re-prompts until it gives up.
        if lines.contains(where: { $0.contains("Enter passphrase:") }) { return .passwordProtected }
        if lines.contains(where: { $0.contains("Unrecognized archive format") || $0.hasPrefix("tar: Error reading archive") }) {
            return .unreadableSource
        }
        guard let first = lines.first else { return .archiveFailed("") }
        return .archiveFailed(first.hasPrefix("tar: ") ? String(first.dropFirst(5)) : first)
    }
}
