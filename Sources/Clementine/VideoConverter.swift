import AVFoundation
import UniformTypeIdentifiers

struct VideoConverter: Converter {
    let inputs: [UTType] = [.quickTimeMovie, .mpeg4Movie]
    let outputs: [OutputFormat] = [.mp4, .mov, .m4a]

    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        assert(outputs.contains(format))
        switch format {
        case .m4a:
            try await MediaExport.exportAudio(source, to: destination)
        default:
            let fileType: AVFileType = format == .mp4 ? .mp4 : .mov
            // Rewrapping the existing streams is lossless and fast, but only works when the codecs
            // fit the new container (ProRes doesn't fit MP4); otherwise re-encode.
            let canRewrap = await AVAssetExportSession.compatibility(
                ofExportPreset: AVAssetExportPresetPassthrough,
                with: AVURLAsset(url: source),
                outputFileType: fileType
            )
            let preset = canRewrap ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
            try await MediaExport.export(source, preset: preset, as: fileType, to: destination)
        }
    }
}
