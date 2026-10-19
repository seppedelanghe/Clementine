import CoreImage
import Foundation

// A turned copy beside the original, for photos taken sideways.
enum Rotate {
    enum Option: Hashable, CaseIterable {
        case left
        case right
        case halfTurn

        var title: String {
            switch self {
            case .left: "90° Left"
            case .right: "90° Right"
            case .halfTurn: "180°"
            }
        }

        // The EXIF orientation that displays an upright image turned this way.
        fileprivate var orientation: CGImagePropertyOrientation {
            switch self {
            case .left: .left
            case .right: .right
            case .halfTurn: .down
            }
        }
    }

    static let title = "Rotate"

    static func item(for files: [URL]) -> WheelItem? {
        guard files.allSatisfy({ ImageConverter.editableType(of: $0) != nil }) else { return nil }
        let items = Option.allCases.map { WheelItem(title: $0.title, symbol: nil, action: .rotate($0)) }
        return WheelItem(title: title, symbol: "rotate.right", action: .open(items))
    }

    // Images keep their format: "photo.jpg" becomes "photo (Rotated).jpg".
    static func run(
        _ files: [URL],
        to option: Option,
        progress: @escaping @Sendable (_ fileIndex: Int) -> Void
    ) async throws {
        for (index, file) in files.enumerated() {
            progress(index)
            guard let type = ImageConverter.editableType(of: file) else { throw ConversionError.unsupportedSource }
            let directory = file.deletingLastPathComponent()
            let workspace = try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: directory,
                create: true
            )
            defer { try? FileManager.default.removeItem(at: workspace) }

            let (image, metadata) = try ImageConverter.read(file)
            let turned = CIImage(cgImage: image).oriented(option.orientation)
            // The source's colour space, so a Display P3 photo isn't flattened to sRGB.
            guard
                let rotated = CIContext().createCGImage(
                    turned,
                    from: turned.extent,
                    format: .RGBA8,
                    colorSpace: image.colorSpace?.model == .rgb ? image.colorSpace : nil
                )
            else { throw ConversionError.writeFailed }
            let temporary = workspace.appending(path: "output")
            try ImageConverter.write(rotated, metadata: metadata, as: type, to: temporary)

            let destination = FileManager.default.availableURL(
                base: "\(try FileManager.baseName(of: file)) (Rotated)",
                suffix: file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)",
                in: directory
            )
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
