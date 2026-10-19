import Foundation
import UniformTypeIdentifiers

// Registered after the AVFoundation converters, so these only take the pairs those can't handle.
struct FFmpegVideoConverter: Converter {
    let inputs: [UTType] = [.movie]
    let outputs: [OutputFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .m4a, .mp3]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        try await FFmpeg.convert(source, to: format, destination: destination, progress: progress)
    }
}

struct FFmpegAudioConverter: Converter {
    let inputs: [UTType] = [.audio]
    let outputs: [OutputFormat] = [.mp3, .m4a, .wav, .aiff, .flac, .ogg, .opus, .wma]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        try await FFmpeg.convert(source, to: format, destination: destination, progress: progress)
    }
}

enum FFmpeg {
    static func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        try await run(["-i", source.path] + arguments(for: format) + [destination.path], progress: progress)
    }

    // HEVC for sending, at a lower quality than Convert's H.264: a 1080p screen recording comes
    // out at about a tenth of its size. The shorter side becomes `height`, and is never enlarged.
    static func shrink(
        _ source: URL,
        toHeight height: Int,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        let side = { (dimension: String) in "trunc(min(\(height),\(dimension))/2)*2" }
        let scale = "scale=w='if(gte(iw,ih),-2,\(side("iw")))':h='if(gte(iw,ih),\(side("ih")),-2)'"
        try await run(
            [
                "-i", source.path, "-sn", "-dn", "-vf", scale,
                // Apple's players only accept HEVC in MP4 under the hvc1 tag.
                "-c:v", "hevc_videotoolbox", "-q:v", "50", "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
                "-c:a", "aac_at", "-b:a", "128k", "-movflags", "+faststart", "-f", "mp4", destination.path,
            ],
            progress: progress
        )
    }

    // Sets the rotation players apply instead of turning the pixels, so the streams are copied
    // untouched and it takes no time. `degrees` is clockwise and replaces the video's own.
    static func rotate(_ source: URL, to degrees: Int, muxer: String, destination: URL, progress: @escaping ProgressHandler)
        async throws
    {
        try await run(
            [
                "-display_rotation:v:0", String(-degrees), "-i", source.path,
                "-map", "0:v", "-map", "0:a?", "-c", "copy", "-f", muxer, destination.path,
            ],
            progress: progress
        )
    }

    // Every other stream is copied as it is. The muxer follows `destination`'s extension, which
    // names it for every video container.
    static func removeAudio(_ source: URL, destination: URL) async throws {
        try await run(
            ["-i", source.path, "-map", "0", "-map", "-0:a", "-map", "-0:d", "-c", "copy", destination.path],
            progress: { _ in }
        )
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

    private static func run(_ arguments: [String], progress: ProgressHandler) async throws {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg") else {
            preconditionFailure("ffmpeg is missing from the app bundle")
        }
        let process = Process()
        process.executableURL = executable
        // Progress goes to stderr too, so one reader sees the input's duration before the
        // out_time_us lines that need it. Log lines are tagged with their level to pick out errors.
        process.arguments = [
            "-nostdin", "-hide_banner", "-nostats", "-loglevel", "level+info",
            "-progress", "pipe:2", "-stats_period", "0.5", "-y",
        ] + arguments
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
        // ffmpeg states the cause first and ends with generic summaries, so the first errors are kept.
        var errorLines: [String] = []
        var duration: Double?
        for try await line in errors.fileHandleForReading.bytes.lines {
            if line.hasPrefix("out_time_us="), let duration, let microseconds = Double(line.dropFirst(12)) {
                progress(min(microseconds / 1_000_000 / duration, 1))
            } else if duration == nil, let range = line.range(of: "Duration: ") {
                duration = seconds(line[range.upperBound...].prefix(11))
            } else if line.contains("[error] ") || line.contains("[fatal] "), errorLines.count < 50 {
                errorLines.append(line)
            }
        }
        for await status in exits where status != 0 {
            throw error(from: errorLines)
        }
    }

    // "HH:MM:SS.xx" as printed in ffmpeg's Duration line; nil for "N/A" or a zero length.
    private static func seconds(_ timestamp: Substring) -> Double? {
        let parts = timestamp.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        let total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return total > 0 ? total : nil
    }

    private static func error(from lines: [String]) -> ConversionError {
        if lines.contains(where: { $0.contains("Invalid data found when processing input") }) {
            return .unreadableSource
        }
        if lines.contains(where: { $0.contains("does not contain any stream") }) { return .noAudioTrack }
        guard var message = lines.first.map({ Substring($0) }) else { return .ffmpegFailed("") }
        // Drop the "[component @ 0x…] [error] " tags; they mean nothing to the user.
        while message.hasPrefix("["), let end = message.range(of: "] ") {
            message = message[end.upperBound...]
        }
        return .ffmpegFailed(String(message))
    }
}
