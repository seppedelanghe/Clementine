import AppKit
import UniformTypeIdentifiers

// Cocoa's own document importers and exporters, for the formats they handle without losing
// content: RTF is Cocoa's native format, and HTML and plain text carry little layout to lose.
struct TextDocumentConverter: Converter {
    // Plain text by conformance, so CSV and source code are offered these outputs too.
    let inputs: [UTType] = [.rtf, .html, .plainText]
    let excludedInputs: [UTType] = [.markdown]
    let outputs: [OutputFormat] = [.pdf, .docx, .rtf, .html, .txt]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        // The HTML importer and the text view that lays out PDF pages both need the main thread.
        try await MainActor.run {
            let (document, attributes) = try Self.read(source)
            try Self.write(document, attributes: attributes, as: format, to: destination)
        }
    }

    // Paper size, margins and metadata come along, so the output keeps them where it has room.
    @MainActor
    static func read(_ source: URL) throws -> (NSAttributedString, [NSAttributedString.DocumentAttributeKey: Any]) {
        var attributes: NSDictionary?
        guard let document = try? NSAttributedString(url: source, options: [:], documentAttributes: &attributes) else {
            throw ConversionError.unreadableSource
        }
        return (document, attributes as? [NSAttributedString.DocumentAttributeKey: Any] ?? [:])
    }

    @MainActor
    static func write(
        _ document: NSAttributedString,
        attributes: [NSAttributedString.DocumentAttributeKey: Any],
        as format: OutputFormat,
        to destination: URL
    ) throws {
        if format == .pdf {
            try writePDF(document, attributes: attributes, to: destination)
            return
        }
        var attributes = attributes
        attributes[.documentType] =
            switch format {
            case .docx: NSAttributedString.DocumentType.officeOpenXML
            case .rtf: NSAttributedString.DocumentType.rtf
            case .html: NSAttributedString.DocumentType.html
            case .txt: NSAttributedString.DocumentType.plain
            default: preconditionFailure("No document type for \(format.title)")
            }
        attributes[.characterEncoding] = String.Encoding.utf8.rawValue
        guard
            var data = try? document.data(
                from: NSRange(location: 0, length: document.length),
                documentAttributes: attributes
            )
        else { throw ConversionError.writeFailed }
        if format == .html { data = Data(embeddingImages(of: document, in: String(decoding: data, as: UTF8.self)).utf8) }
        try data.write(to: destination)
    }

    // Cocoa's HTML writer points each image at a made-up "file:///Attachment.png" and writes no
    // image files, so the images go into the page as data URLs instead, matched in document order.
    @MainActor
    private static func embeddingImages(of document: NSAttributedString, in html: String) -> String {
        var images: [NSTextAttachment] = []
        document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { images.append(attachment) }
        }
        let tags = try! NSRegularExpression(pattern: #"<img src="[^"]*""#)
            .matches(in: html, range: NSRange(html.startIndex..., in: html))
        // Pairing by position is only safe when every attachment produced exactly one tag.
        guard tags.count == images.count else { return html }

        var output = html
        for (tag, attachment) in zip(tags, images).reversed() {
            guard let source = dataURL(for: attachment) else { continue }
            let width = attachment.bounds.width > 0 ? " width=\"\(Int(attachment.bounds.width))\"" : ""
            output.replaceSubrange(Range(tag.range, in: output)!, with: "<img src=\"\(source)\"\(width)")
        }
        return output
    }

    @MainActor
    private static func dataURL(for attachment: NSTextAttachment) -> String? {
        if
            let data = attachment.contents ?? attachment.fileWrapper?.regularFileContents,
            let type = attachment.fileType.flatMap(UTType.init),
            let mimeType = type.preferredMIMEType
        {
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
        guard
            let image = attachment.image,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
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
