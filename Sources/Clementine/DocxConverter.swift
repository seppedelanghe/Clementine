import Foundation
import OSLog
import UniformTypeIdentifiers

// Registered before TextDocumentConverter, which keeps every other DOCX output and is the fallback
// here: a text-only PDF beats no PDF when docxide-pdf can't lay a document out.
struct DocxConverter: Converter {
    private static let logger = Logger(subsystem: "be.seppedelanghe.clementine", category: "docx")

    let inputs: [UTType] = [OutputFormat.docx.type]
    let outputs: [OutputFormat] = [.pdf]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        do {
            try await Self.render(source, to: destination)
        } catch {
            Self.logger.error(
                "docxide-pdf failed on \(source.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            try await TextDocumentConverter().convert(source, to: format, destination: destination, progress: progress)
        }
    }

    private struct RenderFailure: Error {
        let status: Int32
        let message: String
    }

    private static func render(_ source: URL, to destination: URL) async throws {
        guard
            let executable = Bundle.main.url(forAuxiliaryExecutable: "docxide-pdf"),
            let fonts = Bundle.main.resourceURL?.appending(path: "Fonts")
        else { preconditionFailure("docxide-pdf or its fonts are missing from the app bundle") }

        let process = Process()
        process.executableURL = executable
        process.arguments = [source.path, destination.path]
        // Carlito and Caladea, the stand-ins for Calibri and Cambria. 0.18.4 still spells the
        // variable DOCXSIDE_FONTS; later releases renamed it DOCXIDE_FONTS.
        process.environment = ProcessInfo.processInfo.environment.merging(["DOCXSIDE_FONTS": fonts.path]) { $1 }
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

        var errorLines: [String] = []
        for try await line in errors.fileHandleForReading.bytes.lines where errorLines.count < 50 {
            errorLines.append(line)
        }
        for await status in exits where status != 0 {
            throw RenderFailure(status: status, message: errorLines.joined(separator: "\n"))
        }
    }
}
