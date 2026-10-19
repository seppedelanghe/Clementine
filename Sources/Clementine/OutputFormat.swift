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
    static let mkv = OutputFormat(
        title: "MKV",
        type: UTType(importedAs: "org.matroska.mkv", conformingTo: .movie),
        fileExtension: "mkv",
        symbol: "film"
    )
    static let webm = OutputFormat(
        title: "WebM",
        type: UTType(importedAs: "org.webmproject.webm", conformingTo: .movie),
        fileExtension: "webm",
        symbol: "film"
    )
    static let avi = OutputFormat(title: "AVI", type: .avi, fileExtension: "avi", symbol: "film")
    static let wmv = OutputFormat(
        title: "WMV",
        type: UTType(importedAs: "com.microsoft.windows-media-wmv", conformingTo: .movie),
        fileExtension: "wmv",
        symbol: "film"
    )
    static let gif = OutputFormat(title: "GIF", type: .gif, fileExtension: "gif", symbol: "film")

    static let m4a = OutputFormat(title: "M4A", type: .mpeg4Audio, fileExtension: "m4a", symbol: "waveform")
    static let wav = OutputFormat(title: "WAV", type: .wav, fileExtension: "wav", symbol: "waveform")
    static let aiff = OutputFormat(title: "AIFF", type: .aiff, fileExtension: "aiff", symbol: "waveform")
    static let flac = OutputFormat(title: "FLAC", type: UTType("org.xiph.flac")!, fileExtension: "flac", symbol: "waveform")
    static let mp3 = OutputFormat(title: "MP3", type: .mp3, fileExtension: "mp3", symbol: "waveform")
    static let ogg = OutputFormat(
        title: "OGG",
        type: UTType(importedAs: "org.xiph.ogg-audio", conformingTo: .audio),
        fileExtension: "ogg",
        symbol: "waveform"
    )
    // Recent macOS treats .ogg and .opus as one type, so these two are never offered to each other.
    static let opus = OutputFormat(
        title: "Opus",
        type: UTType(importedAs: "org.xiph.opus", conformingTo: .audio),
        fileExtension: "opus",
        symbol: "waveform"
    )
    static let wma = OutputFormat(
        title: "WMA",
        type: UTType(importedAs: "com.microsoft.windows-media-wma", conformingTo: .audio),
        fileExtension: "wma",
        symbol: "waveform"
    )

    static let zip = OutputFormat(title: "ZIP", type: .zip, fileExtension: "zip", symbol: "doc.zipper")
    static let sevenZip = OutputFormat(
        title: "7z",
        type: UTType("org.7-zip.7-zip-archive")!,
        fileExtension: "7z",
        symbol: "doc.zipper"
    )
    static let tar = OutputFormat(title: "TAR", type: UTType("public.tar-archive")!, fileExtension: "tar", symbol: "doc.zipper")
    // Typed as plain gzip and xz, which is what macOS gives ".tar.gz" and ".tar.xz" files, so
    // those are never offered a conversion to themselves.
    static let tarGz = OutputFormat(title: "TAR.GZ", type: .gzip, fileExtension: "tar.gz", symbol: "doc.zipper")
    static let tarXz = OutputFormat(
        title: "TAR.XZ",
        type: UTType("org.tukaani.xz-archive")!,
        fileExtension: "tar.xz",
        symbol: "doc.zipper"
    )
}
