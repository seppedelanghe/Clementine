import AVFoundation
import CoreImage
import UniformTypeIdentifiers

// A turned copy beside the original, for photos and videos taken sideways.
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

        fileprivate var degrees: Int {
            switch self {
            case .left: -90
            case .right: 90
            case .halfTurn: 180
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
    // The containers whose rotation players honour; Matroska, AVI and the rest would need the
    // video re-encoded.
    private static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie]

    static func item(for files: [URL]) -> WheelItem? {
        guard files.allSatisfy({ ImageConverter.editableType(of: $0) != nil || videoType(of: $0) != nil }) else {
            return nil
        }
        let items = Option.allCases.map { WheelItem(title: $0.title, symbol: nil, action: .rotate($0)) }
        return WheelItem(title: title, symbol: "rotate.right", action: .open(items))
    }

    // Files keep their format: "photo.jpg" becomes "photo (Rotated).jpg".
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
            if let type = ImageConverter.editableType(of: file) {
                try rotateImage(file, by: option, as: type, to: temporary)
            } else if let type = videoType(of: file) {
                let degrees = try await rotation(of: file) + option.degrees
                try await FFmpeg.rotate(
                    file,
                    to: degrees,
                    muxer: type == .quickTimeMovie ? "mov" : "mp4",
                    destination: temporary
                ) { progress(index, $0) }
            } else {
                throw ConversionError.unsupportedSource
            }

            let destination = FileManager.default.availableURL(
                base: "\(try FileManager.baseName(of: file)) (Rotated)",
                suffix: file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)",
                in: directory
            )
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func rotateImage(_ file: URL, by option: Option, as type: UTType, to destination: URL) throws {
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
        try ImageConverter.write(rotated, metadata: metadata, as: type, to: destination)
    }

    // Clockwise, which is how AVFoundation's transforms turn with the origin at the top left.
    // Phones record portrait videos as landscape turned 90°.
    private static func rotation(of video: URL) async throws -> Int {
        guard let track = try await AVURLAsset(url: video).loadTracks(withMediaType: .video).first else {
            throw ConversionError.unreadableSource
        }
        let transform = try await track.load(.preferredTransform)
        return Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    }

    private static func videoType(of file: URL) -> UTType? {
        guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
        return videoTypes.first(where: type.conforms(to:))
    }
}
