import AppKit
import UniformTypeIdentifiers

// Foundation parses the Markdown but leaves the look to us: its result only says which block each
// run belongs to. MarkdownStyle turns those blocks into paragraphs, lists, quotes, code blocks and
// tables that Cocoa's document writers and the PDF printer understand.
struct MarkdownConverter: Converter {
    let inputs: [UTType] = [UTType("net.daringfireball.markdown")!]
    let outputs: [OutputFormat] = [.pdf, .docx, .rtf, .odt, .html, .txt]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        // The base URL resolves relative image paths against the Markdown file's folder.
        guard
            let text = try? String(contentsOf: source, encoding: .utf8),
            let markdown = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible),
                baseURL: source
            )
        else { throw ConversionError.unreadableSource }

        try await MainActor.run {
            try TextDocumentConverter.write(MarkdownStyle().render(markdown), attributes: [:], as: format, to: destination)
        }
    }
}

@MainActor
private final class MarkdownStyle {
    // Fonts every Mac has, so DOCX and RTF output names a real font rather than the system UI font.
    private static let body = NSFont(name: "Helvetica Neue", size: 11)!
    private static let mono = NSFont(name: "Menlo", size: 10)!
    private static let headingSizes: [CGFloat] = [22, 18, 15, 13, 12, 11]
    private static let listIndent: CGFloat = 22
    // A4's width less an inch either side, the narrowest text column the PDF printer uses.
    private static let maxImageWidth: CGFloat = 451

    // Paragraphs of one quote, code block or table share one block object; that is what makes
    // them draw as one box.
    private var blocks: [Int: NSTextBlock] = [:]
    private var tables: [Int: NSTextTable] = [:]
    private var markedListItems: Set<Int> = []

    func render(_ markdown: AttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var currentBlock: Int?
        var hangsMarker = false
        var lastAttributes: [NSAttributedString.Key: Any] = [:]

        for run in markdown.runs {
            guard let intent = run.presentationIntent, let innermost = intent.components.first else { continue }

            var marker: String?
            if innermost.identity != currentBlock {
                // The newline ends the previous paragraph, so it carries that paragraph's style.
                if currentBlock != nil { output.append(NSAttributedString(string: "\n", attributes: lastAttributes)) }
                currentBlock = innermost.identity
                marker = listMarker(for: intent)
                hangsMarker = marker != nil
            }
            var attributes = blockAttributes(for: intent, hangsMarker: hangsMarker)
            if let marker { output.append(NSAttributedString(string: marker, attributes: attributes)) }

            var text = String(markdown[run.range].characters)
            switch innermost.kind {
            // Lines in a code block become paragraphs of their own; the last newline would add an empty one.
            case .codeBlock where text.hasSuffix("\n"): text.removeLast()
            // The parser's "⸻" stands in for the rule, which the block's border draws instead.
            case .thematicBreak: text = "\u{00A0}"
            default: break
            }

            let inline = run.inlinePresentationIntent ?? []
            // A hard line break stays inside its paragraph.
            if inline.contains(.lineBreak) { text = "\u{2028}" }
            applyInline(inline, link: run.link, to: &attributes)

            if let image = run.imageURL.flatMap(Self.attachment(for:)) {
                let piece = NSMutableAttributedString(attachment: image)
                piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
                output.append(piece)
            } else {
                output.append(NSAttributedString(string: text, attributes: attributes))
            }
            lastAttributes = attributes
        }
        return output
    }

    // Only a list item's first paragraph gets the bullet or number.
    private func listMarker(for intent: PresentationIntent) -> String? {
        let components = intent.components
        guard
            let index = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
            case .listItem(let ordinal) = components[index].kind,
            markedListItems.insert(components[index].identity).inserted
        else { return nil }
        if index + 1 < components.count, case .orderedList = components[index + 1].kind { return "\(ordinal).\t" }
        return "•\t"
    }

    // Components run innermost first, so styles are built from the outermost block inwards.
    private func blockAttributes(for intent: PresentationIntent, hangsMarker: Bool) -> [NSAttributedString.Key: Any] {
        var font = Self.body
        var color: NSColor?
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        var indent: CGFloat = 0
        var textBlocks: [NSTextBlock] = []
        var table: NSTextTable?
        var columns: [PresentationIntent.TableColumn] = []
        var row = 0

        for component in intent.components.reversed() {
            switch component.kind {
            case .header(let level):
                font = NSFontManager.shared.convert(
                    Self.body.withSize(Self.headingSizes[min(level, 6) - 1]),
                    toHaveTrait: .boldFontMask
                )
                paragraph.paragraphSpacingBefore = 10
                paragraph.paragraphSpacing = 6
            case .listItem:
                indent += Self.listIndent
                paragraph.paragraphSpacing = 3
            case .blockQuote:
                color = .darkGray
                textBlocks.append(block(component.identity) {
                    let block = Self.fullWidthBlock()
                    block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                    block.setBorderColor(.lightGray, for: .minX)
                    block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                    block.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                    return block
                })
            case .codeBlock:
                font = Self.mono
                paragraph.paragraphSpacing = 0
                textBlocks.append(block(component.identity) {
                    let block = Self.fullWidthBlock()
                    block.backgroundColor = NSColor(white: 0.95, alpha: 1)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    block.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                    return block
                })
            case .table(let tableColumns):
                columns = tableColumns
                table = tables[component.identity] ?? {
                    let table = NSTextTable()
                    table.numberOfColumns = tableColumns.count
                    table.collapsesBorders = true
                    table.setValue(100, type: .percentageValueType, for: .width)
                    table.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                    tables[component.identity] = table
                    return table
                }()
            case .tableHeaderRow:
                row = 0
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            case .tableRow(let rowIndex):
                row = rowIndex
            case .tableCell(let column):
                // The parser only ever puts cells inside a table.
                let table = table!
                paragraph.paragraphSpacing = 0
                paragraph.alignment =
                    switch columns[column].alignment {
                    case .center: .center
                    case .right: .right
                    default: .left
                    }
                textBlocks.append(block(component.identity) { [row] in
                    let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                    cell.setBorderColor(.gray)
                    cell.setWidth(4, type: .absoluteValueType, for: .padding)
                    if row == 0 { cell.backgroundColor = NSColor(white: 0.93, alpha: 1) }
                    return cell
                })
            case .thematicBreak:
                textBlocks.append(block(component.identity) {
                    let block = Self.fullWidthBlock()
                    block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .maxY)
                    block.setBorderColor(.lightGray, for: .maxY)
                    block.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                    return block
                })
            default:
                break
            }
        }

        paragraph.headIndent = indent
        // The marker hangs left of the text, which starts at the tab stop.
        paragraph.firstLineHeadIndent = hangsMarker ? indent - Self.listIndent : indent
        if hangsMarker { paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)] }
        paragraph.textBlocks = textBlocks
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        if let color { attributes[.foregroundColor] = color }
        return attributes
    }

    private func applyInline(
        _ inline: InlinePresentationIntent,
        link: URL?,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        var font = attributes[.font] as! NSFont
        if inline.contains(.code) {
            font = Self.mono.withSize(font.pointSize - 1)
            attributes[.backgroundColor] = NSColor(white: 0.93, alpha: 1)
        }
        if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        attributes[.font] = font
        if let link {
            attributes[.link] = link
            // Text views only colour links on screen; printed and exported text needs its own.
            attributes[.foregroundColor] = NSColor(srgbRed: 0, green: 0.4, blue: 0.8, alpha: 1)
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
    }

    // A block without a width lays its text out zero points wide, one character per line.
    private static func fullWidthBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        return block
    }

    private func block(_ identity: Int, make: () -> NSTextBlock) -> NSTextBlock {
        if let block = blocks[identity] { return block }
        let block = make()
        blocks[identity] = block
        return block
    }

    // Remote images would mean downloading during a conversion, so those keep their alt text.
    private static func attachment(for url: URL) -> NSTextAttachment? {
        guard
            url.isFileURL,
            let data = try? Data(contentsOf: url),
            let image = NSImage(data: data),
            let type = UTType(filenameExtension: url.pathExtension)
        else { return nil }
        let attachment = NSTextAttachment(data: data, ofType: type.identifier)
        // Without the image set as well, the attachment draws at the file's pixel size.
        attachment.image = image
        let scale = min(1, maxImageWidth / image.size.width)
        attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        return attachment
    }
}
