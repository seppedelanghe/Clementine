import Foundation
import UniformTypeIdentifiers

protocol Converter: Sendable {
    var inputs: [UTType] { get }
    var outputs: [OutputFormat] { get }
}

struct ConverterRegistry: Sendable {
    let converters: [any Converter]

    // Formats every file can be converted to, in the order the first file's converters list them.
    func formats(for files: [URL]) -> [OutputFormat] {
        assert(!files.isEmpty)
        let perFile = files.map(formats(for:))
        return perFile[0].filter { format in perFile.allSatisfy { $0.contains(format) } }
    }

    private func formats(for file: URL) -> [OutputFormat] {
        // A file whose metadata can't be read can't be converted either; it simply offers nothing.
        guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return [] }

        var formats: [OutputFormat] = []
        for converter in converters where converter.inputs.contains(where: type.conforms(to:)) {
            for format in converter.outputs where !type.conforms(to: format.type) && !formats.contains(format) {
                formats.append(format)
            }
        }
        return formats
    }
}
