import Foundation

struct ConversionFailure: Sendable {
    let file: URL
    let error: any Error
}

struct ConversionRunner: Sendable {
    let registry: ConverterRegistry

    // Files convert one after another so outputs that would share a name get distinct numbers.
    func run(_ files: [URL], to format: OutputFormat) async -> [ConversionFailure] {
        var failures: [ConversionFailure] = []
        for file in files {
            do {
                try await convert(file, to: format)
            } catch {
                failures.append(ConversionFailure(file: file, error: error))
            }
        }
        return failures
    }

    // Converts into a temporary folder on the same volume and moves the result into place,
    // so a failed conversion never leaves a partial file beside the original.
    private func convert(_ file: URL, to format: OutputFormat) async throws {
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
        try await converter.convert(file, to: format, destination: temporary)
        try FileManager.default.moveItem(at: temporary, to: Self.availableDestination(for: file, as: format))
    }

    // Finder-style numbering: "photo.png", then "photo 2.png", "photo 3.png", …
    private static func availableDestination(for file: URL, as format: OutputFormat) -> URL {
        let directory = file.deletingLastPathComponent()
        let base = file.deletingPathExtension().lastPathComponent
        var candidate = directory.appending(path: "\(base).\(format.fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(number).\(format.fileExtension)")
            number += 1
        }
        return candidate
    }
}
