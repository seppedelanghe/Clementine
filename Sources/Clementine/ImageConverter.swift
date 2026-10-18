import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ImageConverter: Converter {
    private static let lossyQuality = 0.85

    let inputs: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .webP]
    let outputs: [OutputFormat] = [.jpeg, .png, .heic, .tiff, .pdf]

    // Only the first frame is converted, so an animated GIF becomes a still image.
    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        assert(outputs.contains(format))
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
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw ConversionError.unreadableSource
        }

        if format == .pdf {
            try writePDF(image, to: destination)
        } else {
            try writeImage(image, metadata: metadata, as: format, to: destination)
        }
    }

    private func writeImage(
        _ image: CGImage,
        metadata: [CFString: Any],
        as format: OutputFormat,
        to destination: URL
    ) throws {
        // Nil when the system has no encoder for the type, e.g. HEIC on older hardware.
        guard
            let imageDestination = CGImageDestinationCreateWithURL(
                destination as CFURL,
                format.type.identifier as CFString,
                1,
                nil
            )
        else { throw ConversionError.encoderUnavailable }

        var properties = metadata
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties[kCGImageDestinationLossyCompressionQuality] = Self.lossyQuality
        // JPEG has no alpha channel; without a background, transparent areas turn black.
        properties[kCGImageDestinationBackgroundColor] = CGColor.white

        CGImageDestinationAddImage(imageDestination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else { throw ConversionError.writeFailed }
    }

    private func writePDF(_ image: CGImage, to destination: URL) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let page = PDFPage(image: nsImage, options: [.compressionQuality: Self.lossyQuality]) else {
            throw ConversionError.writeFailed
        }
        let document = PDFDocument()
        document.insert(page, at: 0)
        guard document.write(to: destination) else { throw ConversionError.writeFailed }
    }
}
