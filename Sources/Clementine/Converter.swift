import Foundation
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case unreadableSource
    case unsupportedSource
    case noAudioTrack
    case encoderUnavailable
    case writeFailed
    case ffmpegFailed(String)
    case passwordProtected
    case archiveFailed(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .unreadableSource: "The file could not be read."
        case .unsupportedSource: "The file changed before it could be converted."
        case .noAudioTrack: "The file has no audio track."
        case .encoderUnavailable: "This Mac can't write this format."
        case .writeFailed: "The converted file could not be written."
        case .ffmpegFailed(let message): message.isEmpty ? "The conversion failed." : message
        case .passwordProtected: "The file is password-protected."
        case .archiveFailed(let message): message.isEmpty ? "The conversion failed." : message
        case .noText: "The PDF has no text to extract; scanned pages are images."
        }
    }
}

// Fraction of the current file done, 0...1. Converters that finish quickly never call it.
typealias ProgressHandler = @Sendable (Double) -> Void

protocol Converter: Sendable {
    var inputs: [UTType] { get }
    // Subtypes of the inputs this converter leaves to another one.
    var excludedInputs: [UTType] { get }
    var outputs: [OutputFormat] { get }

    func convert(_ source: URL, to format: OutputFormat, destination: URL, progress: @escaping ProgressHandler) async throws
}

extension Converter {
    var excludedInputs: [UTType] { [] }

    func accepts(_ type: UTType) -> Bool {
        inputs.contains(where: type.conforms(to:)) && !excludedInputs.contains(where: type.conforms(to:))
    }
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
            converter.accepts(type) && converter.outputs.contains(format)
        }
    }

    private func formats(for file: URL) -> [OutputFormat] {
        guard let type = Self.contentType(of: file) else { return [] }

        var formats: [OutputFormat] = []
        for converter in converters where converter.accepts(type) {
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
