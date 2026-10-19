import AppKit
import UniformTypeIdentifiers

// Cocoa's own document importers and exporters. They keep text, styles, lists and simple tables;
// page layout such as headers, footers, columns and floating images is lost.
struct TextDocumentConverter: Converter {
    // Plain text by conformance, so Markdown, CSV and source code are offered these outputs too.
    let inputs: [UTType] = [OutputFormat.docx.type, .doc, .rtf, OutputFormat.odt.type, .html, .plainText]
    let outputs: [OutputFormat] = [.pdf, .docx, .rtf, .odt, .html, .txt]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        // The HTML importer and the text view that lays out PDF pages both need the main thread.
        try await MainActor.run {
            var readAttributes: NSDictionary?
            guard let document = try? NSAttributedString(url: source, options: [:], documentAttributes: &readAttributes) else {
                throw ConversionError.unreadableSource
            }
            // Paper size, margins and metadata carry over to the output where it has room for them.
            var attributes = readAttributes as? [NSAttributedString.DocumentAttributeKey: Any] ?? [:]

            if format == .pdf {
                try Self.writePDF(document, attributes: attributes, to: destination)
                return
            }
            attributes[.documentType] =
                switch format {
                case .docx: NSAttributedString.DocumentType.officeOpenXML
                case .rtf: NSAttributedString.DocumentType.rtf
                case .odt: NSAttributedString.DocumentType.openDocument
                case .html: NSAttributedString.DocumentType.html
                case .txt: NSAttributedString.DocumentType.plain
                default: preconditionFailure("No document type for \(format.title)")
                }
            attributes[.characterEncoding] = String.Encoding.utf8.rawValue
            guard
                let data = try? document.data(
                    from: NSRange(location: 0, length: document.length),
                    documentAttributes: attributes
                )
            else { throw ConversionError.writeFailed }
            try data.write(to: destination)
        }
    }

    // A print job saved to a file splits pages on line boundaries; pdfOperation and dataWithPDF
    // would put the whole document on one tall page.
    @MainActor
    private static func writePDF(
        _ document: NSAttributedString,
        attributes: [NSAttributedString.DocumentAttributeKey: Any],
        to destination: URL
    ) throws {
        // Documents without their own paper size and margins get the locale's paper and an inch
        // all round; NSPrintInfo's own margins are zero when no printer is set up.
        let printInfo = NSPrintInfo()
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        if let paper = attributes[.paperSize] as? NSValue { printInfo.paperSize = paper.sizeValue }
        if let margin = attributes[.leftMargin] as? CGFloat { printInfo.leftMargin = margin }
        if let margin = attributes[.rightMargin] as? CGFloat { printInfo.rightMargin = margin }
        if let margin = attributes[.topMargin] as? CGFloat { printInfo.topMargin = margin }
        if let margin = attributes[.bottomMargin] as? CGFloat { printInfo.bottomMargin = margin }
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        // TextKit 1, because TextKit 2 falls back to it for tables anyway.
        let textView = NSTextView(usingTextLayoutManager: false)
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        textView.isVerticallyResizable = true
        // Without these, Dark Mode prints a dark page and text without a colour of its own in white.
        textView.appearance = NSAppearance(named: .aqua)
        textView.drawsBackground = false
        textView.textStorage?.setAttributedString(document)
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ConversionError.writeFailed }
    }
}

private extension UTType {
    static let doc = UTType("com.microsoft.word.doc")!
}
