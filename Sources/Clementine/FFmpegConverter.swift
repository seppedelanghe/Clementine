import Foundation
import UniformTypeIdentifiers

// Registered after the AVFoundation converters, so these only take the pairs those can't handle.
struct FFmpegVideoConverter: Converter {
    let inputs: [UTType] = [.movie]
    let outputs: [OutputFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .m4a, .mp3]

    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        assert(outputs.contains(format))
        try await FFmpeg.convert(source, to: format, destination: destination)
    }
}

struct FFmpegAudioConverter: Converter {
    let inputs: [UTType] = [.audio]
    let outputs: [OutputFormat] = [.mp3, .m4a, .wav, .aiff, .flac, .ogg, .opus, .wma]

    func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        assert(outputs.contains(format))
        try await FFmpeg.convert(source, to: format, destination: destination)
    }
}

enum FFmpeg {
    static func convert(_ source: URL, to format: OutputFormat, destination: URL) async throws {
        try await run(["-i", source.path] + arguments(for: format) + [destination.path])
    }

    // Fixed defaults per output; docs/ffmpeg.md has the reasoning. The muxer is always explicit
    // because the extension alone doesn't select it (M4A needs ipod, WMA needs asf).
    private static func arguments(for format: OutputFormat) -> [String] {
        let h264 = ["-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p", "-c:a", "aac_at", "-b:a", "192k"]
        // Cover art in audio files arrives as a video stream that audio muxers reject.
        let audioOnly = ["-vn"]
        let streams: [String]
        switch format {
        case .mp4: streams = h264 + ["-movflags", "+faststart", "-f", "mp4"]
        case .mov: streams = h264 + ["-f", "mov"]
        // Matroska holds nearly any codec, so the streams are copied as they are.
        case .mkv: streams = ["-c", "copy", "-f", "matroska"]
        case .webm:
            streams = [
                "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-cpu-used", "4",
                "-c:a", "libopus", "-b:a", "128k", "-f", "webm",
            ]
        case .avi: streams = ["-c:v", "mpeg4", "-q:v", "3", "-tag:v", "xvid", "-c:a", "libmp3lame", "-q:a", "2", "-f", "avi"]
        case .wmv: streams = ["-c:v", "wmv2", "-q:v", "3", "-c:a", "wmav2", "-b:a", "192k", "-f", "asf"]
        case .gif:
            streams = [
                "-vf", "fps=15,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                "-an", "-loop", "0", "-f", "gif",
            ]
        case .mp3: streams = audioOnly + ["-c:a", "libmp3lame", "-q:a", "2", "-f", "mp3"]
        case .m4a: streams = audioOnly + ["-c:a", "aac_at", "-b:a", "256k", "-f", "ipod"]
        case .wav: streams = audioOnly + ["-c:a", "pcm_s16le", "-f", "wav"]
        case .aiff: streams = audioOnly + ["-c:a", "pcm_s16be", "-f", "aiff"]
        case .flac: streams = audioOnly + ["-c:a", "flac", "-f", "flac"]
        case .ogg: streams = audioOnly + ["-c:a", "libvorbis", "-q:a", "5", "-f", "ogg"]
        case .opus: streams = audioOnly + ["-c:a", "libopus", "-b:a", "128k", "-f", "opus"]
        case .wma: streams = audioOnly + ["-c:a", "wmav2", "-b:a", "192k", "-f", "asf"]
        default: preconditionFailure("No ffmpeg arguments for \(format.title)")
        }
        // Subtitle and data streams rarely convert between containers and would fail the whole run.
        return ["-sn", "-dn"] + streams
    }

    private static func run(_ arguments: [String]) async throws {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg") else {
            preconditionFailure("ffmpeg is missing from the app bundle")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y"] + arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        let exits = AsyncStream<Int32> { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }
        try process.run()

        // Drained while ffmpeg runs: a damaged file can log enough to fill the pipe and stall it.
        // ffmpeg states the cause first and ends with generic summaries, so the opening lines are kept.
        var lines: [String] = []
        for try await line in errors.fileHandleForReading.bytes.lines where lines.count < 50 {
            lines.append(line)
        }
        for await status in exits where status != 0 {
            throw error(from: lines)
        }
    }

    private static func error(from lines: [String]) -> ConversionError {
        if lines.contains(where: { $0.contains("Invalid data found when processing input") }) {
            return .unreadableSource
        }
        if lines.contains(where: { $0.contains("does not contain any stream") }) { return .noAudioTrack }
        guard let first = lines.first else { return .ffmpegFailed("") }
        // Drop ffmpeg's "[component @ 0x…] " prefix; it means nothing to the user.
        if first.hasPrefix("["), let end = first.range(of: "] ") {
            return .ffmpegFailed(String(first[end.upperBound...]))
        }
        return .ffmpegFailed(first)
    }
}
