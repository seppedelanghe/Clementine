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
    case automationDenied
    case pagesFailed(String)

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
        case .automationDenied:
            "Clementine isn't allowed to control Pages. Allow it in System Settings under Privacy & Security, Automation."
        case .pagesFailed(let message): message.isEmpty ? "Pages couldn't export the document." : message
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
        guard let type = Self.contentType(of: file), !Self.isOwnFormat(format, of: file, type: type) else { return nil }
        return converters.first { converter in
            converter.accepts(type) && converter.outputs.contains(format)
        }
    }

    private func formats(for file: URL) -> [OutputFormat] {
        guard let type = Self.contentType(of: file) else { return [] }

        var formats: [OutputFormat] = []
        for converter in converters where converter.accepts(type) {
            for format in converter.outputs where !Self.isOwnFormat(format, of: file, type: type) && !formats.contains(format) {
                formats.append(format)
            }
        }
        return formats
    }

    // The extension catches what the type misses: macOS types .opus files as Ogg audio.
    private static func isOwnFormat(_ format: OutputFormat, of file: URL, type: UTType) -> Bool {
        type.conforms(to: format.type) || file.lastPathComponent.lowercased().hasSuffix(".\(format.fileExtension)")
    }

    // A file whose metadata can't be read can't be converted either; it simply offers nothing.
    private static func contentType(of file: URL) -> UTType? {
        try? file.resourceValues(forKeys: [.contentTypeKey]).contentType
    }
}
