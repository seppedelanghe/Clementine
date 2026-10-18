import AVFoundation

enum MediaExport {
    static func export(
        _ source: URL,
        preset: String,
        as fileType: AVFileType,
        to destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.encoderUnavailable
        }
        session.outputURL = destination
        session.outputFileType = fileType
        // Export sessions only expose progress by polling, and the session isn't Sendable before
        // macOS 15, so this task both waits and polls instead of handing it to a second task.
        session.exportAsynchronously {}
        while session.status == .waiting || session.status == .exporting {
            progress(Double(session.progress))
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard session.status == .completed else { throw session.error ?? ConversionError.writeFailed }
    }

    static func exportAudio(_ source: URL, to destination: URL, progress: @escaping ProgressHandler) async throws {
        guard try await !AVURLAsset(url: source).loadTracks(withMediaType: .audio).isEmpty else {
            throw ConversionError.noAudioTrack
        }
        try await export(source, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: destination, progress: progress)
    }
}
