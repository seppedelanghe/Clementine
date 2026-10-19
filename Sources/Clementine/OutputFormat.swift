import UniformTypeIdentifiers

struct OutputFormat: Hashable, Sendable {
    let title: String
    let type: UTType
    // Explicit because UTType's preferred extension isn't always the familiar one (jpeg vs jpg).
    let fileExtension: String
}

extension OutputFormat {
    static let jpeg = OutputFormat(title: "JPG", type: .jpeg, fileExtension: "jpg")
    static let png = OutputFormat(title: "PNG", type: .png, fileExtension: "png")
    static let heic = OutputFormat(title: "HEIC", type: .heic, fileExtension: "heic")
    static let tiff = OutputFormat(title: "TIFF", type: .tiff, fileExtension: "tiff")
    static let pdf = OutputFormat(title: "PDF", type: .pdf, fileExtension: "pdf")

    static let mp4 = OutputFormat(title: "MP4", type: .mpeg4Movie, fileExtension: "mp4")
    static let mov = OutputFormat(title: "MOV", type: .quickTimeMovie, fileExtension: "mov")
    static let mkv = OutputFormat(
        title: "MKV",
        type: UTType(importedAs: "org.matroska.mkv", conformingTo: .movie),
        fileExtension: "mkv"
    )
    static let webm = OutputFormat(
        title: "WebM",
        type: UTType(importedAs: "org.webmproject.webm", conformingTo: .movie),
        fileExtension: "webm"
    )
    static let avi = OutputFormat(title: "AVI", type: .avi, fileExtension: "avi")
    static let wmv = OutputFormat(
        title: "WMV",
        type: UTType(importedAs: "com.microsoft.windows-media-wmv", conformingTo: .movie),
        fileExtension: "wmv"
    )
    static let gif = OutputFormat(title: "GIF", type: .gif, fileExtension: "gif")

    static let m4a = OutputFormat(title: "M4A", type: .mpeg4Audio, fileExtension: "m4a")
    static let wav = OutputFormat(title: "WAV", type: .wav, fileExtension: "wav")
    static let aiff = OutputFormat(title: "AIFF", type: .aiff, fileExtension: "aiff")
    static let flac = OutputFormat(title: "FLAC", type: UTType("org.xiph.flac")!, fileExtension: "flac")
    static let mp3 = OutputFormat(title: "MP3", type: .mp3, fileExtension: "mp3")
    static let ogg = OutputFormat(
        title: "OGG",
        type: UTType(importedAs: "org.xiph.ogg-audio", conformingTo: .audio),
        fileExtension: "ogg"
    )
    // Recent macOS treats .ogg and .opus as one type, so these two are never offered to each other.
    static let opus = OutputFormat(
        title: "Opus",
        type: UTType(importedAs: "org.xiph.opus", conformingTo: .audio),
        fileExtension: "opus"
    )
    static let wma = OutputFormat(
        title: "WMA",
        type: UTType(importedAs: "com.microsoft.windows-media-wma", conformingTo: .audio),
        fileExtension: "wma"
    )

    static let zip = OutputFormat(title: "ZIP", type: .zip, fileExtension: "zip")
    static let sevenZip = OutputFormat(
        title: "7z",
        type: UTType("org.7-zip.7-zip-archive")!,
        fileExtension: "7z"
    )
    static let tar = OutputFormat(title: "TAR", type: UTType("public.tar-archive")!, fileExtension: "tar")
    // Typed as plain gzip and xz, which is what macOS gives ".tar.gz" and ".tar.xz" files, so
    // those are never offered a conversion to themselves.
    static let tarGz = OutputFormat(title: "TAR.GZ", type: .gzip, fileExtension: "tar.gz")
    static let tarXz = OutputFormat(
        title: "TAR.XZ",
        type: UTType("org.tukaani.xz-archive")!,
        fileExtension: "tar.xz"
    )

    static let docx = OutputFormat(
        title: "DOCX",
        type: UTType("org.openxmlformats.wordprocessingml.document")!,
        fileExtension: "docx"
    )
    static let rtf = OutputFormat(title: "RTF", type: .rtf, fileExtension: "rtf")
    static let html = OutputFormat(title: "HTML", type: .html, fileExtension: "html")
    static let txt = OutputFormat(title: "TXT", type: .plainText, fileExtension: "txt")
    static let epub = OutputFormat(title: "EPUB", type: UTType("org.idpf.epub-container")!, fileExtension: "epub")
}
