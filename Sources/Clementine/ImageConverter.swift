import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ImageConverter: Converter {
    private static let lossyQuality = 0.85

    let inputs: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .webP]
    let outputs: [OutputFormat] = [.jpeg, .png, .heic, .tiff, .pdf]
    // The formats ImageIO can also write, so an edited image keeps its format; GIFs would lose
    // their animation.
    private static let editableTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .bmp]

    static func editableType(of file: URL) -> UTType? {
        guard let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
        return editableTypes.first(where: type.conforms(to:))
    }

    // Only the first frame is converted, so an animated GIF becomes a still image.
    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        let (image, metadata) = try Self.read(source)
        if format == .pdf {
            try writePDF(image, to: destination)
        } else {
            try Self.write(image, metadata: metadata, as: format.type, to: destination)
        }
    }

    // `scale` applies to the width and height.
    static func read(_ source: URL, scale: Double = 1) throws -> (CGImage, metadata: [CFString: Any]) {
        assert(scale > 0 && scale <= 1)
        guard
            let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let width = metadata[kCGImagePropertyPixelWidth] as? Int,
            let height = metadata[kCGImagePropertyPixelHeight] as? Int
        else { throw ConversionError.unreadableSource }

        // Bakes the EXIF orientation into the pixels: not every output carries the tag
        // (PNG viewers commonly ignore it), so the result must be upright on its own.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, (Double(max(width, height)) * scale).rounded()),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw ConversionError.unreadableSource
        }
        return (image, metadata)
    }

    static func write(_ image: CGImage, metadata: [CFString: Any], as type: UTType, to destination: URL) throws {
        // Nil when the system has no encoder for the type, e.g. HEIC on older hardware.
        guard
            let imageDestination = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw ConversionError.encoderUnavailable }

        var properties = metadata
        // The source's flag; a JPEG's false would drop the alpha of an image cut out from it.
        properties[kCGImagePropertyHasAlpha] = nil
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            properties[kCGImagePropertyExifDictionary] = exif
        }
        properties[kCGImageDestinationLossyCompressionQuality] = Self.lossyQuality
        // JPEG has no alpha channel; without a background, transparent areas turn black.
        properties[kCGImageDestinationBackgroundColor] = CGColor.white

        CGImageDestinationAddImage(imageDestination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else { throw ConversionError.writeFailed }
    }

    static func pdfPage(_ image: CGImage) throws -> PDFPage {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let page = PDFPage(image: nsImage, options: [.compressionQuality: lossyQuality]) else {
            throw ConversionError.writeFailed
        }
        return page
    }

    private func writePDF(_ image: CGImage, to destination: URL) throws {
        let document = PDFDocument()
        document.insert(try Self.pdfPage(image), at: 0)
        guard document.write(to: destination) else { throw ConversionError.writeFailed }
    }
}
