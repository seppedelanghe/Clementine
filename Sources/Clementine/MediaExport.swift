import AVFoundation

enum MediaExport {
    static func export(_ source: URL, preset: String, as fileType: AVFileType, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.encoderUnavailable
        }
        session.outputURL = destination
        session.outputFileType = fileType
        // The throwing export(to:as:) needs macOS 15.
        await session.export()
        guard session.status == .completed else { throw session.error ?? ConversionError.writeFailed }
    }

    static func exportAudio(_ source: URL, to destination: URL) async throws {
        guard try await !AVURLAsset(url: source).loadTracks(withMediaType: .audio).isEmpty else {
            throw ConversionError.noAudioTrack
        }
        try await export(source, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: destination)
    }
}
