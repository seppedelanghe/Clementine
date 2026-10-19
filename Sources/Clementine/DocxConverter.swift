import Foundation
import OSLog
import UniformTypeIdentifiers

// PDF through docxide-pdf, which lays pages out like Word. Cocoa's importer only gets the text
// right, so it provides TXT, and a text-only PDF when docxide-pdf can't lay a document out.
struct DocxConverter: Converter {
    private static let logger = Logger(subsystem: "be.seppedelanghe.clementine", category: "docx")

    let inputs: [UTType] = [OutputFormat.docx.type]
    let outputs: [OutputFormat] = [.pdf, .txt]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        if format == .pdf {
            do {
                try await Self.render(source, to: destination)
                return
            } catch {
                Self.logger.error(
                    "docxide-pdf failed on \(source.path, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        try await TextDocumentConverter.convert(source, to: format, destination: destination)
    }

    private static func render(_ source: URL, to destination: URL) async throws {
        guard
            let executable = Bundle.main.url(forAuxiliaryExecutable: "docxide-pdf"),
            let fonts = Bundle.main.resourceURL?.appending(path: "Fonts")
        else { preconditionFailure("docxide-pdf or its fonts are missing from the app bundle") }

        // Carlito and Caladea, the stand-ins for Calibri and Cambria. 0.18.4 still spells the
        // variable DOCXSIDE_FONTS; later releases renamed it DOCXIDE_FONTS.
        try await Subprocess.run(
            executable,
            arguments: [source.path, destination.path],
            environment: ["DOCXSIDE_FONTS": fonts.path]
        )
    }
}
