import Foundation
import UniformTypeIdentifiers

// A smaller copy beside the original, in the same format, for sending.
enum Shrink {
    static let title = "Shrink"
    // Of the width and height, so 50% leaves about a quarter of the pixels.
    private static let scales = [0.25, 0.5, 0.75, 0.9]
    // The formats ImageIO can also write; GIFs would lose their animation.
    private static let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .bmp]

    static func item(for files: [URL]) -> WheelItem? {
        guard files.allSatisfy({ imageType(of: $0) != nil }) else { return nil }
        let options = scales.map { WheelItem(title: $0.formatted(.percent), symbol: nil, action: .shrink($0)) }
        return WheelItem(title: title, symbol: "arrow.down.right.and.arrow.up.left", action: .open(options))
    }

    // "photo.jpg" at 50% becomes "photo (50%).jpg".
    static func images(_ files: [URL], to scale: Double) async throws {
        for file in files {
            guard let type = imageType(of: file) else { throw ConversionError.unsupportedSource }
            let directory = file.deletingLastPathComponent()
            let workspace = try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: directory,
                create: true
            )
            defer { try? FileManager.default.removeItem(at: workspace) }

            let temporary = workspace.appending(path: file.lastPathComponent)
            let (image, metadata) = try ImageConverter.read(file, scale: scale)
            try ImageConverter.write(image, metadata: metadata, as: type, to: temporary)
            let destination = FileManager.default.availableURL(
                base: "\(try FileManager.baseName(of: file)) (\(scale.formatted(.percent)))",
                suffix: file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)",
                in: directory
            )
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func imageType(of file: URL) -> UTType? {
        guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
        return imageTypes.first(where: type.conforms(to:))
    }
}
