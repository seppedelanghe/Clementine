import Foundation

struct ConversionFailure: Sendable {
    let file: URL
    let error: any Error
}

struct ConversionRunner: Sendable {
    let registry: ConverterRegistry

    // Files convert one after another so outputs that would share a name get distinct numbers.
    // `progress` receives the index of the file being converted and how far along it is.
    func run(
        _ files: [URL],
        to format: OutputFormat,
        progress: @escaping @Sendable (_ fileIndex: Int, _ fraction: Double) -> Void
    ) async -> [ConversionFailure] {
        var failures: [ConversionFailure] = []
        for (index, file) in files.enumerated() {
            progress(index, 0)
            do {
                try await convert(file, to: format) { progress(index, $0) }
            } catch {
                failures.append(ConversionFailure(file: file, error: error))
            }
        }
        return failures
    }

    // Converts into a temporary folder on the same volume and moves the result into place,
    // so a failed conversion never leaves a partial file beside the original.
    private func convert(_ file: URL, to format: OutputFormat, progress: @escaping ProgressHandler) async throws {
        guard let converter = registry.converter(for: file, to: format) else {
            throw ConversionError.unsupportedSource
        }

        let directory = file.deletingLastPathComponent()
        let workspace = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: directory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let temporary = workspace.appending(path: "output.\(format.fileExtension)")
        try await converter.convert(file, to: format, destination: temporary, progress: progress)
        let destination = FileManager.default.availableURL(
            base: try FileManager.baseName(of: file),
            suffix: ".\(format.fileExtension)",
            in: directory
        )
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

extension FileManager {
    // Finder-style numbering: "photo.png", then "photo 2.png", "photo 3.png", …
    func availableURL(base: String, suffix: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: base + suffix)
        var number = 2
        while fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(number)\(suffix)")
            number += 1
        }
        return candidate
    }

    // "name.tar.gz" has the base name "name", so it converts to "name.zip", not "name.tar.zip".
    // A folder's base name is its whole name, dots included.
    static func baseName(of item: URL) throws -> String {
        let name = item.lastPathComponent
        if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { return name }
        var base = (name as NSString).deletingPathExtension
        if base.hasSuffix(".tar") { base.removeLast(4) }
        return base
    }
}
