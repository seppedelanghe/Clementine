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
        try FileManager.default.moveItem(at: temporary, to: Self.availableDestination(for: file, as: format))
    }

    // Finder-style numbering: "photo.png", then "photo 2.png", "photo 3.png", …
    private static func availableDestination(for file: URL, as format: OutputFormat) -> URL {
        let directory = file.deletingLastPathComponent()
        var base = file.deletingPathExtension().lastPathComponent
        // "name.tar.gz" becomes "name.zip", not "name.tar.zip".
        if base.hasSuffix(".tar") { base.removeLast(4) }
        var candidate = directory.appending(path: "\(base).\(format.fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(number).\(format.fileExtension)")
            number += 1
        }
        return candidate
    }
}
