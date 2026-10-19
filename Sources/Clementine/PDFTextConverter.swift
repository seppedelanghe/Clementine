import AppKit
import PDFKit
import UniformTypeIdentifiers

// Text only: PDFKit gives each line's text with its fonts and colours. A PDF stores no paragraphs,
// so they are rebuilt from where the lines sit on the page.
struct PDFTextConverter: Converter {
    let inputs: [UTType] = [.pdf]
    let outputs: [OutputFormat] = [.docx, .txt]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        try await Self.convert(source, to: format, destination: destination)
    }

    @MainActor
    private static func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        guard let pdf = PDFDocument(url: source) else { throw ConversionError.unreadableSource }
        guard !pdf.isLocked else { throw ConversionError.passwordProtected }

        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.map(lines(of:))
        let running = runningLines(in: pages)
        let document = NSMutableAttributedString()
        for lines in pages {
            let text = paragraphs(from: lines.filter { !running.contains(key(for: $0)) })
            guard text.length > 0 else { continue }
            // A form feed is a page break in DOCX; plain text gets a blank line.
            if document.length > 0 { document.append(NSAttributedString(string: format == .txt ? "\n\n" : "\n\u{0C}")) }
            document.append(text)
        }
        // Scanned pages are images; there is no text to extract without OCR.
        guard document.length > 0 else { throw ConversionError.noText }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        document.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: document.length))
        try await TextDocumentConverter.write(document, attributes: [:], as: format, to: destination)
    }

    private struct Line {
        let text: NSAttributedString
        let box: CGRect
        let page: CGRect
    }

    @MainActor
    private static func lines(of page: PDFPage) -> [Line] {
        let bounds = page.bounds(for: .cropBox)
        guard let selections = page.selection(for: bounds)?.selectionsByLine() else { return [] }
        return selections.compactMap { selection in
            // Lines of only symbols or object placeholders are decoration, not text.
            guard
                let text = selection.attributedString.map(trimmed),
                text.string.contains(where: { $0.isLetter || $0.isNumber })
            else { return nil }
            return Line(text: text, box: selection.bounds(for: page), page: bounds)
        }
    }

    // Running headers and footers: text in the top or bottom tenth of the page that repeats on at
    // least half the pages, page numbers aside. Kept, they would interrupt the text on every page.
    private static func runningLines(in pages: [[Line]]) -> Set<String> {
        guard pages.count >= 3 else { return [] }
        var counts: [String: Int] = [:]
        for lines in pages {
            let edges = lines.filter { line in
                let margin = line.page.height * 0.1
                return line.box.minY > line.page.maxY - margin || line.box.maxY < line.page.minY + margin
            }
            for key in Set(edges.map(key(for:))) { counts[key, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value * 2 >= pages.count }.keys)
    }

    private static func key(for line: Line) -> String {
        String(line.text.string.map { $0.isNumber ? "#" : $0 })
    }

    // A line continues the paragraph above it when it follows at ordinary line spacing in the same
    // font size, and the line above ran (nearly) to the right edge of the text.
    private static func paragraphs(from lines: [Line]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let left = lines.map(\.box.minX).min() ?? 0
        let right = lines.map(\.box.maxX).max() ?? 0

        var previous: Line?
        for line in lines {
            let text = line.text
            if let previous {
                // PDF coordinates grow upwards, so the gap is the previous line's bottom less this line's top.
                let gap = previous.box.minY - line.box.maxY
                let continues =
                    gap > -line.box.height * 0.2 && gap < line.box.height * 0.6
                    && fontSize(of: previous.text, at: previous.text.length - 1) == fontSize(of: text, at: 0)
                    && previous.box.maxX > left + (right - left) * 0.85
                if !continues {
                    output.append(NSAttributedString(string: "\n"))
                } else if output.string.hasSuffix("-"), text.string.first?.isLowercase == true {
                    // A word hyphenated across the line break.
                    output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
                } else {
                    output.append(NSAttributedString(string: " ", attributes: text.attributes(at: 0, effectiveRange: nil)))
                }
            }
            output.append(text)
            previous = line
        }
        return output
    }

    private static func fontSize(of text: NSAttributedString, at index: Int) -> CGFloat? {
        (text.attribute(.font, at: index, effectiveRange: nil) as? NSFont).map { ($0.pointSize * 2).rounded() / 2 }
    }

    private static func trimmed(_ text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        var start = 0
        var end = string.length
        while start < end, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: start)) ?? " ") { start += 1 }
        while end > start, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: end - 1)) ?? " ") { end -= 1 }
        return text.attributedSubstring(from: NSRange(location: start, length: end - start))
    }
}
