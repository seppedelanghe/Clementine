import AVFoundation
import UniformTypeIdentifiers

struct AudioConverter: Converter {
    let inputs: [UTType] = [
        .mp3, .mpeg4Audio, .wav, .aiff, UTType("public.aac-audio")!, UTType("org.xiph.flac")!,
    ]
    let outputs: [OutputFormat] = [.m4a, .wav, .aiff, .flac]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        if format == .m4a {
            try await MediaExport.exportAudio(source, to: destination, progress: progress)
        } else {
            try transcode(source, as: format, to: destination, progress: progress)
        }
    }

    // Export sessions can't write WAV, AIFF or FLAC, so decode and re-encode with AVAudioFile.
    // The container comes from the destination's extension.
    private func transcode(
        _ source: URL,
        as format: OutputFormat,
        to destination: URL,
        progress: ProgressHandler
    ) throws {
        let input = try AVAudioFile(forReading: source)
        let processing = input.processingFormat
        var settings: [String: Any] = [
            AVSampleRateKey: processing.sampleRate,
            AVNumberOfChannelsKey: processing.channelCount,
        ]
        if format == .flac {
            // Written from float samples this is always 24-bit FLAC: lossless for sources up to
            // 24-bit, and only ~1% larger than 16-bit for 16-bit sources.
            settings[AVFormatIDKey] = kAudioFormatFLAC
        } else {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = format == .aiff
        }
        let output = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: processing.commonFormat,
            interleaved: processing.isInterleaved
        )

        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 1 << 16) else {
            throw ConversionError.writeFailed
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
            progress(Double(input.framePosition) / Double(input.length))
        }
    }
}
