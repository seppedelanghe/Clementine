import Foundation
import UniformTypeIdentifiers

enum ConversionError: Error {
    case unreadableSource
    case unsupportedSource
    case encoderUnavailable
    case writeFailed
}

protocol Converter: Sendable {
    var inputs: [UTType] { get }
    var outputs: [OutputFormat] { get }

    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws
}

struct ConverterRegistry: Sendable {
    let converters: [any Converter]

    // Formats every file can be converted to, in the order the first file's converters list them.
    func formats(for files: [URL]) -> [OutputFormat] {
        assert(!files.isEmpty)
        let perFile = files.map(formats(for:))
        return perFile[0].filter { format in perFile.allSatisfy { $0.contains(format) } }
    }

    // Nil when the file changed or vanished after the wheel offered the format.
    func converter(for file: URL, to format: OutputFormat) -> (any Converter)? {
        guard let type = Self.contentType(of: file), !type.conforms(to: format.type) else { return nil }
        return converters.first { converter in
            converter.inputs.contains(where: type.conforms(to:)) && converter.outputs.contains(format)
        }
    }

    private func formats(for file: URL) -> [OutputFormat] {
        guard let type = Self.contentType(of: file) else { return [] }

        var formats: [OutputFormat] = []
        for converter in converters where converter.inputs.contains(where: type.conforms(to:)) {
            for format in converter.outputs where !type.conforms(to: format.type) && !formats.contains(format) {
                formats.append(format)
            }
        }
        return formats
    }

    // A file whose metadata can't be read can't be converted either; it simply offers nothing.
    private static func contentType(of file: URL) -> UTType? {
        try? file.resourceValues(forKeys: [.contentTypeKey]).contentType
    }
}
