import AVFoundation
import UniformTypeIdentifiers

struct AudioConverter: Converter {
    let inputs: [UTType] = [
        .mp3, .mpeg4Audio, .wav, .aiff, UTType("public.aac-audio")!, UTType("org.xiph.flac")!,
    ]
    let outputs: [OutputFormat] = [.m4a, .wav, .aiff]

    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        assert(outputs.contains(format))
        if format == .m4a {
            try await MediaExport.exportAudio(source, to: destination)
        } else {
            try writePCM(source, bigEndian: format == .aiff, to: destination)
        }
    }

    // Export sessions can't write WAV or AIFF from compressed audio, so decode and write PCM
    // directly. The container comes from the destination's extension.
    private func writePCM(_ source: URL, bigEndian: Bool, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: bigEndian,
        ]
        let output = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else {
            throw ConversionError.writeFailed
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}
