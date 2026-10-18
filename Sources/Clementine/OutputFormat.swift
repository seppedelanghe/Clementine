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

    static let mp4 = OutputFormat(title: "MP4", type: .mpeg4Movie, fileExtension: "mp4", symbol: "film")
    static let mov = OutputFormat(title: "MOV", type: .quickTimeMovie, fileExtension: "mov", symbol: "film")

    static let m4a = OutputFormat(title: "M4A", type: .mpeg4Audio, fileExtension: "m4a", symbol: "waveform")
    static let wav = OutputFormat(title: "WAV", type: .wav, fileExtension: "wav", symbol: "waveform")
    static let aiff = OutputFormat(title: "AIFF", type: .aiff, fileExtension: "aiff", symbol: "waveform")
    static let flac = OutputFormat(title: "FLAC", type: UTType("org.xiph.flac")!, fileExtension: "flac", symbol: "waveform")
}
