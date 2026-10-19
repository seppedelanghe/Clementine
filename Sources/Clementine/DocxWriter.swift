import AppKit
import UniformTypeIdentifiers

// Cocoa's own DOCX writer drops tables, images and paragraph shading. This writes what an
// NSAttributedString holds: paragraphs with indents, spacing, alignment, tabs, borders and shading;
// runs with font, size, bold, italic, colour, highlight, underline, strikethrough and links;
// tables, inline images, and line and page breaks.
//
// WordprocessingML is strict about element order inside the property blocks (pPr, rPr, tblPr,
// tcPr); Word reports a file as damaged when they're out of schema order.
@MainActor
final class DocxWriter {
    private static let twipsPerPoint: CGFloat = 20
    private static let emuPerPoint: CGFloat = 12_700

    private var body = ""
    private var relationships: [String] = []
    private var media: [(name: String, data: Data)] = []
    private var contentWidth: CGFloat = 0

    static func write(
        _ document: NSAttributedString,
        attributes: [NSAttributedString.DocumentAttributeKey: Any],
        to destination: URL
    ) async throws {
        let workspace = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let files = try DocxWriter().package(document, attributes: attributes, in: workspace)
        try await BSDTar.run(["-c", "--format", "zip", "-f", destination.path, "-C", workspace.path] + files)
    }

    // Returns the package's files, content types first, which is where readers look for them.
    private func package(
        _ document: NSAttributedString,
        attributes: [NSAttributedString.DocumentAttributeKey: Any],
        in directory: URL
    ) throws -> [String] {
        // Like the PDF writer: the document's own paper and margins, else the locale's paper and an inch.
        let paper = (attributes[.paperSize] as? NSValue)?.sizeValue ?? NSPrintInfo().paperSize
        let margins = [
            attributes[.topMargin] as? CGFloat ?? 72, attributes[.rightMargin] as? CGFloat ?? 72,
            attributes[.bottomMargin] as? CGFloat ?? 72, attributes[.leftMargin] as? CGFloat ?? 72,
        ]
        contentWidth = paper.width - margins[1] - margins[3]
        relationships.append(Self.relationship("rId1", type: "styles", target: "styles.xml"))
        writeBody(document)

        let section = """
            <w:sectPr><w:pgSz w:w="\(Self.twips(paper.width))" w:h="\(Self.twips(paper.height))"/>\
            <w:pgMar w:top="\(Self.twips(margins[0]))" w:right="\(Self.twips(margins[1]))" \
            w:bottom="\(Self.twips(margins[2]))" w:left="\(Self.twips(margins[3]))" \
            w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
            """
        let files: [(String, String)] = [
            ("[Content_Types].xml", Self.contentTypes),
            ("_rels/.rels", Self.packageRelationships),
            ("word/document.xml", "\(Self.xmlHeader)<w:document \(Self.namespaces)><w:body>\(body)\(section)</w:body></w:document>"),
            ("word/styles.xml", Self.styles),
            (
                "word/_rels/document.xml.rels",
                "\(Self.xmlHeader)<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                    + relationships.joined() + "</Relationships>"
            ),
        ]
        for (path, xml) in files {
            let url = directory.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: url)
        }
        if !media.isEmpty {
            try FileManager.default.createDirectory(at: directory.appending(path: "word/media"), withIntermediateDirectories: true)
            for (name, data) in media { try data.write(to: directory.appending(path: "word/media/\(name)")) }
        }
        return files.map(\.0) + media.map { "word/media/\($0.name)" }
    }

    // MARK: Body

    private func writeBody(_ document: NSAttributedString) {
        let string = document.string as NSString
        var paragraphs: [NSRange] = []
        var location = 0
        while location < string.length {
            var end = 0
            var contentsEnd = 0
            string.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            paragraphs.append(NSRange(location: location, length: contentsEnd - location))
            location = end
        }

        // Consecutive paragraphs inside cells of one NSTextTable make up one table.
        var table: NSTextTable?
        var cells: [(paragraph: NSRange, cell: NSTextTableBlock)] = []
        var spaceBefore: CGFloat = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let cell = Self.paragraphStyle(of: document, at: paragraph)?.textBlocks.lazy.compactMap { $0 as? NSTextTableBlock }.first
            if let cell, cell.table === table {
                cells.append((paragraph, cell))
                continue
            }
            if let table {
                body += tableXML(table, cells: cells, in: document)
                // Word has no space below a table; the paragraph after it takes the table's margin.
                spaceBefore = table.width(for: .margin, edge: .maxY)
            }
            table = cell?.table
            cells = cell.map { [(paragraph, $0)] } ?? []
            if cell == nil {
                let next = paragraphs.indices.contains(index + 1)
                    ? Self.paragraphStyle(of: document, at: paragraphs[index + 1]) : nil
                body += paragraphXML(document, range: paragraph, next: next, spaceBefore: spaceBefore)
                spaceBefore = 0
            }
        }
        if let table {
            body += tableXML(table, cells: cells, in: document)
            // Word wants a paragraph between a table and the section's end.
            body += "<w:p/>"
        }
    }

    private func paragraphXML(
        _ document: NSAttributedString,
        range: NSRange,
        next: NSParagraphStyle? = nil,
        spaceBefore: CGFloat = 0
    ) -> String {
        let style = Self.paragraphStyle(of: document, at: range)
        var xml = "<w:p>" + paragraphProperties(style, next: next, spaceBefore: spaceBefore)
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        document.enumerateAttributes(in: range) { attributes, range, _ in runs.append((range, attributes)) }

        var openLink: String?
        for (range, attributes) in runs {
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            if link != openLink {
                if openLink != nil { xml += "</w:hyperlink>" }
                if let link {
                    let id = "rId\(relationships.count + 1)"
                    relationships.append(Self.relationship(id, type: "hyperlink", target: link, external: true))
                    xml += "<w:hyperlink r:id=\"\(id)\" w:history=\"1\">"
                }
                openLink = link
            }
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                xml += imageXML(attachment)
            } else {
                xml += runXML((document.string as NSString).substring(with: range), attributes: attributes)
            }
        }
        if openLink != nil { xml += "</w:hyperlink>" }
        return xml + "</w:p>"
    }

    private func paragraphProperties(_ style: NSParagraphStyle?, next: NSParagraphStyle?, spaceBefore: CGFloat) -> String {
        guard let style else { return "" }
        var xml = ""
        let blocks = style.textBlocks.filter { !($0 is NSTextTableBlock) }
        // Quotes, rules and code blocks: their borders and background, per paragraph. Consecutive
        // paragraphs with the same ones join up in Word, as the shared block does in Cocoa.
        var borders = ""
        for (edge, name) in [(NSRectEdge.minY, "top"), (.minX, "left"), (.maxY, "bottom"), (.maxX, "right")] {
            guard let block = blocks.first(where: { $0.width(for: .border, edge: edge) > 0 }) else { continue }
            let width = block.width(for: .border, edge: edge)
            let color = block.borderColor(for: edge).flatMap(Self.hex) ?? "auto"
            let space = Int(block.width(for: .padding, edge: edge).rounded())
            borders += "<w:\(name) w:val=\"single\" w:sz=\"\(max(2, Int(width * 8)))\" w:space=\"\(space)\" w:color=\"\(color)\"/>"
        }
        if !borders.isEmpty { xml += "<w:pBdr>\(borders)</w:pBdr>" }
        if let fill = blocks.lazy.compactMap({ $0.backgroundColor.flatMap(Self.hex) }).first {
            xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(fill)\"/>"
        }
        // Cocoa's default stops every 28 points are Word's default too; only custom ones are written.
        if !style.tabStops.isEmpty, style.tabStops != NSParagraphStyle.default.tabStops {
            xml += "<w:tabs>"
            for tab in style.tabStops {
                let alignment = switch tab.alignment {
                case .center: "center"
                case .right: "right"
                default: "left"
                }
                xml += "<w:tab w:val=\"\(alignment)\" w:pos=\"\(Self.twips(tab.location))\"/>"
            }
            xml += "</w:tabs>"
        }
        // A block's bottom margin goes below its last paragraph, the one the next paragraph doesn't share.
        let blockMargin = blocks
            .filter { block in !(next?.textBlocks.contains { $0 === block } ?? false) }
            .map { $0.width(for: .margin, edge: .maxY) }
            .reduce(0, +)
        let before = style.paragraphSpacingBefore + spaceBefore
        var spacing = "<w:spacing w:before=\"\(Self.twips(before))\" w:after=\"\(Self.twips(style.paragraphSpacing + blockMargin))\""
        if style.lineHeightMultiple > 0 { spacing += " w:line=\"\(Int(240 * style.lineHeightMultiple))\" w:lineRule=\"auto\"" }
        xml += spacing + "/>"

        let left = style.headIndent
        let firstLine = style.firstLineHeadIndent - style.headIndent
        if left != 0 || firstLine != 0 {
            xml += "<w:ind w:left=\"\(Self.twips(left))\""
            if firstLine < 0 { xml += " w:hanging=\"\(Self.twips(-firstLine))\"" }
            if firstLine > 0 { xml += " w:firstLine=\"\(Self.twips(firstLine))\"" }
            xml += "/>"
        }
        switch style.alignment {
        case .center: xml += "<w:jc w:val=\"center\"/>"
        case .right: xml += "<w:jc w:val=\"right\"/>"
        case .justified: xml += "<w:jc w:val=\"both\"/>"
        default: break
        }
        return xml.isEmpty ? "" : "<w:pPr>\(xml)</w:pPr>"
    }

    // Tabs, line breaks and page breaks are elements of their own in a run, not characters.
    private func runXML(_ text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        let properties = Self.runProperties(attributes)
        var xml = ""
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            xml += "<w:r>\(properties)<w:t xml:space=\"preserve\">\(Self.escape(buffer))</w:t></w:r>"
            buffer = ""
        }
        for character in text {
            switch character {
            case "\t":
                flush()
                xml += "<w:r>\(properties)<w:tab/></w:r>"
            case "\u{2028}":
                flush()
                xml += "<w:r>\(properties)<w:br/></w:r>"
            case "\u{0C}":
                flush()
                xml += "<w:r><w:br w:type=\"page\"/></w:r>"
            default:
                buffer.append(character)
            }
        }
        flush()
        return xml
    }

    private static func runProperties(_ attributes: [NSAttributedString.Key: Any]) -> String {
        var xml = ""
        let font = attributes[.font] as? NSFont
        if let font {
            let family = escape(font.familyName ?? font.fontName)
            xml += "<w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\" w:eastAsia=\"\(family)\" w:cs=\"\(family)\"/>"
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { xml += "<w:b/>" }
            if traits.contains(.italic) { xml += "<w:i/>" }
        }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { xml += "<w:strike/>" }
        if let color = (attributes[.foregroundColor] as? NSColor).flatMap(hex) { xml += "<w:color w:val=\"\(color)\"/>" }
        if let font {
            let halfPoints = Int((font.pointSize * 2).rounded())
            xml += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
        }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { xml += "<w:u w:val=\"single\"/>" }
        if let fill = (attributes[.backgroundColor] as? NSColor).flatMap(hex) {
            xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(fill)\"/>"
        }
        return xml.isEmpty ? "" : "<w:rPr>\(xml)</w:rPr>"
    }

    // MARK: Tables

    private func tableXML(
        _ table: NSTextTable,
        cells: [(paragraph: NSRange, cell: NSTextTableBlock)],
        in document: NSAttributedString
    ) -> String {
        let columns = max(table.numberOfColumns, 1)
        // A cell may hold several paragraphs; they arrive in order, one cell after another.
        var grouped: [(cell: NSTextTableBlock, paragraphs: [NSRange])] = []
        for (paragraph, cell) in cells {
            if grouped.last?.cell === cell { grouped[grouped.count - 1].paragraphs.append(paragraph) }
            else { grouped.append((cell, [paragraph])) }
        }
        let rows = Dictionary(grouping: grouped, by: \.cell.startingRow).sorted { $0.key < $1.key }

        // Widths in twips: Word reads percentages, but other readers (Quick Look among them) don't.
        // A table without a width of its own fits its content, as it does in Cocoa and HTML.
        let tableWidth: CGFloat? = switch table.valueType(for: .width) {
        case .percentageValueType where table.value(for: .width) > 0: contentWidth * table.value(for: .width) / 100
        case .absoluteValueType where table.value(for: .width) > 0: min(table.value(for: .width), contentWidth)
        default: nil
        }
        let columnWidth = (tableWidth ?? contentWidth) / CGFloat(columns)
        var xml = "<w:tbl><w:tblPr>"
        xml += tableWidth.map { "<w:tblW w:w=\"\(Self.twips($0))\" w:type=\"dxa\"/>" } ?? "<w:tblW w:w=\"0\" w:type=\"auto\"/>"
        if let bordered = grouped.first(where: { $0.cell.width(for: .border, edge: .minX) > 0 })?.cell {
            let size = max(2, Int(bordered.width(for: .border, edge: .minX) * 8))
            let color = bordered.borderColor(for: .minX).flatMap(Self.hex) ?? "auto"
            xml += "<w:tblBorders>"
            for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                xml += "<w:\(edge) w:val=\"single\" w:sz=\"\(size)\" w:space=\"0\" w:color=\"\(color)\"/>"
            }
            xml += "</w:tblBorders>"
        }
        // Fixed layout makes readers keep the widths instead of shrinking columns to their text.
        xml += "<w:tblLayout w:type=\"\(tableWidth == nil ? "autofit" : "fixed")\"/>"
        xml += "<w:tblCellMar><w:left w:w=\"80\" w:type=\"dxa\"/>"
        xml += "<w:right w:w=\"80\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>"
        xml += String(repeating: "<w:gridCol w:w=\"\(Self.twips(columnWidth))\"/>", count: columns) + "</w:tblGrid>"

        let cellWidth = { (span: Int) in
            tableWidth == nil ? "<w:tcW w:w=\"0\" w:type=\"auto\"/>" : "<w:tcW w:w=\"\(Self.twips(columnWidth * CGFloat(span)))\" w:type=\"dxa\"/>"
        }
        let emptyCell = "<w:tc><w:tcPr>\(cellWidth(1))</w:tcPr><w:p/></w:tc>"
        for (_, cellsInRow) in rows {
            xml += "<w:tr>"
            var column = 0
            for (cell, paragraphs) in cellsInRow.sorted(by: { $0.cell.startingColumn < $1.cell.startingColumn }) {
                // Word needs every grid column filled; Cocoa allows gaps.
                while column < cell.startingColumn {
                    xml += emptyCell
                    column += 1
                }
                let span = min(cell.columnSpan, columns - column)
                xml += "<w:tc><w:tcPr>" + cellWidth(span)
                if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                if let fill = cell.backgroundColor.flatMap(Self.hex) {
                    xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(fill)\"/>"
                }
                xml += "</w:tcPr>" + paragraphs.map { paragraphXML(document, range: $0) }.joined() + "</w:tc>"
                column += span
            }
            while column < columns {
                xml += emptyCell
                column += 1
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    // MARK: Images

    private func imageXML(_ attachment: NSTextAttachment) -> String {
        guard let (data, fileExtension, size) = Self.imageData(of: attachment) else { return "" }
        let number = media.count + 1
        let name = "image\(number).\(fileExtension)"
        media.append((name, data))
        let id = "rId\(relationships.count + 1)"
        relationships.append(Self.relationship(id, type: "image", target: "media/\(name)"))

        // Never wider than the text column, like Word does on insert.
        let scale = min(1, contentWidth / max(size.width, 1))
        let width = Int(size.width * scale * Self.emuPerPoint)
        let height = Int(size.height * scale * Self.emuPerPoint)
        return """
            <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
            <wp:extent cx="\(width)" cy="\(height)"/><wp:docPr id="\(number)" name="Picture \(number)"/>\
            <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <pic:nvPicPr><pic:cNvPr id="\(number)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
            <pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm>\
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>\
            </wp:inline></w:drawing></w:r>
            """
    }

    // PNG, JPEG and GIF go in as they are; anything else Word may not read becomes PNG.
    private static func imageData(of attachment: NSTextAttachment) -> (Data, String, CGSize)? {
        let original = attachment.contents ?? attachment.fileWrapper?.regularFileContents
        guard let image = attachment.image ?? original.flatMap(NSImage.init(data:)) else { return nil }
        let size = attachment.bounds.size == .zero ? image.size : attachment.bounds.size

        if let original, let type = attachment.fileType.flatMap(UTType.init) {
            for (kind, fileExtension) in [(UTType.png, "png"), (.jpeg, "jpeg"), (.gif, "gif")] where type.conforms(to: kind) {
                return (original, fileExtension, size)
            }
        }
        guard
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return (png, "png", size)
    }

    // MARK: Helpers

    private static func paragraphStyle(of document: NSAttributedString, at paragraph: NSRange) -> NSParagraphStyle? {
        // An empty paragraph's style sits on its newline, just past the range.
        let index = min(paragraph.location, document.length - 1)
        guard index >= 0 else { return nil }
        return document.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
    }

    private static func twips(_ points: CGFloat) -> Int {
        Int((points * twipsPerPoint).rounded())
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    // XML 1.0 forbids most control characters, even escaped.
    private static func escape(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "\u{FFFE}", "\u{FFFF}": break
            default: if scalar.value >= 0x20 { escaped.unicodeScalars.append(scalar) }
            }
        }
        return escaped
    }

    private static func relationship(_ id: String, type: String, target: String, external: Bool = false) -> String {
        "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(type)\" "
            + "Target=\"\(escape(target))\"\(external ? " TargetMode=\"External\"" : "")/>"
    }

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private static let namespaces = """
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
        """

    private static let contentTypes = xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="png" ContentType="image/png"/>\
        <Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Default Extension="gif" ContentType="image/gif"/>\
        <Override PartName="/word/document.xml" \
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" \
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        </Types>
        """

    private static let packageRelationships = xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" \
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
        Target="word/document.xml"/></Relationships>
        """

    // Every paragraph and run carries its own formatting, so the defaults only need to stop Word
    // from adding its own spacing and font to text that doesn't say otherwise.
    private static let styles = xmlHeader + """
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:docDefaults><w:rPrDefault><w:rPr>\
        <w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica" w:eastAsia="Helvetica" w:cs="Helvetica"/>\
        <w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault>\
        </w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\
        </w:styles>
        """
}
