import Foundation

// Runs a command-line tool to completion. ffmpeg has its own runner, because it reads progress
// from the same stream while it runs.
enum Subprocess {
    struct Failure: Error {
        let status: Int32
        // The first lines the tool wrote to stderr, where they all say what went wrong.
        let errorLines: [String]
    }

    // `environment` is added to Clementine's own, which the tool otherwise inherits unchanged.
    static func run(_ executable: URL, arguments: [String], environment: [String: String] = [:]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        process.standardInput = FileHandle.nullDevice
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

        // Drained while the tool runs, so a chatty one can't fill the pipe and stall: bsdtar, for
        // one, prompts thousands of times for the password of an encrypted archive.
        var errorLines: [String] = []
        for try await line in errors.fileHandleForReading.bytes.lines where errorLines.count < 50 {
            errorLines.append(line)
        }
        for await status in exits where status != 0 {
            throw Failure(status: status, errorLines: errorLines)
        }
    }
}
