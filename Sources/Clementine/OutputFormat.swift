import UniformTypeIdentifiers

struct OutputFormat: Hashable, Sendable {
    let title: String
    let type: UTType
    // Explicit because UTType's preferred extension isn't always the familiar one (jpeg vs jpg).
    let fileExtension: String
    let symbol: String
}

extension OutputFormat {
    static let jpeg = OutputFormat(title: "JPG", type: .jpeg, fileExtension: "jpg", symbol: "photo")
    static let png = OutputFormat(title: "PNG", type: .png, fileExtension: "png", symbol: "photo")
    static let heic = OutputFormat(title: "HEIC", type: .heic, fileExtension: "heic", symbol: "photo")
    static let tiff = OutputFormat(title: "TIFF", type: .tiff, fileExtension: "tiff", symbol: "photo")
    static let pdf = OutputFormat(title: "PDF", type: .pdf, fileExtension: "pdf", symbol: "doc.richtext")
}
