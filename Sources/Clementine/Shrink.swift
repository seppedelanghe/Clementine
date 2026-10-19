import Foundation
import UniformTypeIdentifiers

// A smaller copy beside the original, for sending.
enum Shrink {
    enum Option: Hashable {
        // Of the width and height, so 50% leaves about a quarter of the pixels.
        case scale(Double)
        // Of the shorter side, so portrait videos shrink like landscape ones.
        case height(Int)

        var title: String {
            switch self {
            case .scale(let scale): scale.formatted(.percent)
            case .height(let height): "\(height)p"
            }
        }
    }

    static let title = "Shrink"
    private static let imageOptions = [0.25, 0.5, 0.75, 0.9].map(Option.scale)
    // Offered whatever the video's own size, since reading it would hold up the wheel; a video
    // is never enlarged.
    private static let videoOptions = [1080, 720, 480].map(Option.height)
    // The formats ImageIO can also write; GIFs would lose their animation.
    private static let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .bmp]

    static func item(for files: [URL]) -> WheelItem? {
        let options: [Option]
        if files.allSatisfy({ imageType(of: $0) != nil }) {
            options = imageOptions
        } else if files.allSatisfy({ contentType(of: $0)?.conforms(to: .movie) == true }) {
            options = videoOptions
        } else {
            return nil
        }
        let items = options.map { WheelItem(title: $0.title, symbol: nil, action: .shrink($0)) }
        return WheelItem(title: title, symbol: "arrow.down.right.and.arrow.up.left", action: .open(items))
    }

    // Images keep their format: "photo.jpg" at 50% becomes "photo (50%).jpg". Videos become MP4:
    // "clip.mkv" at 720p becomes "clip (720p).mp4".
    static func run(
        _ files: [URL],
        to option: Option,
        progress: @escaping @Sendable (_ fileIndex: Int, _ fraction: Double) -> Void
    ) async throws {
        for (index, file) in files.enumerated() {
            progress(index, 0)
            let directory = file.deletingLastPathComponent()
            let workspace = try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: directory,
                create: true
            )
            defer { try? FileManager.default.removeItem(at: workspace) }

            let temporary = workspace.appending(path: "output")
            let fileExtension: String
            switch option {
            case .scale(let scale):
                guard let type = imageType(of: file) else { throw ConversionError.unsupportedSource }
                let (image, metadata) = try ImageConverter.read(file, scale: scale)
                try ImageConverter.write(image, metadata: metadata, as: type, to: temporary)
                fileExtension = file.pathExtension
            case .height(let height):
                try await FFmpeg.shrink(file, toHeight: height, destination: temporary) { progress(index, $0) }
                fileExtension = OutputFormat.mp4.fileExtension
            }
            let destination = FileManager.default.availableURL(
                base: "\(try FileManager.baseName(of: file)) (\(option.title))",
                suffix: fileExtension.isEmpty ? "" : ".\(fileExtension)",
                in: directory
            )
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func imageType(of file: URL) -> UTType? {
        guard let type = contentType(of: file) else { return nil }
        return imageTypes.first(where: type.conforms(to:))
    }

    private static func contentType(of file: URL) -> UTType? {
        try? file.resourceValues(forKeys: [.contentTypeKey]).contentType
    }
}
