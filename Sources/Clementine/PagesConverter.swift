import AppKit
import UniformTypeIdentifiers

// Pages exports its own documents, so the result is what exporting from Pages by hand gives.
// Offered only while Pages is installed; the first export asks for Automation permission.
struct PagesConverter: Converter {
    private static let bundleIdentifier = "com.apple.Pages"

    var inputs: [UTType] {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil else { return [] }
        // The single-file format current Pages saves, and the older package format.
        return [UTType("com.apple.iwork.pages.sffpages")!, UTType("com.apple.iwork.pages.pages")!]
    }
    let outputs: [OutputFormat] = [.pdf, .docx, .rtf, .txt, .epub]

    func convert(
        _ source: URL,
        to format: OutputFormat,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        assert(outputs.contains(format))
        let exportFormat =
            switch format {
            case .pdf: "PDF"
            case .docx: "Microsoft Word"
            case .rtf: "formatted text"
            case .txt: "unformatted text"
            case .epub: "EPUB"
            default: preconditionFailure("No Pages export format for \(format.title)")
            }
        // The paths travel as arguments rather than inside the script, so no file name can change it.
        // Pages is quit again afterwards unless it was already open.
        let script = """
            on run argv
                set wasRunning to application id "\(Self.bundleIdentifier)" is running
                tell application id "\(Self.bundleIdentifier)"
                    try
                        set doc to open (POSIX file (item 1 of argv))
                        export doc to (POSIX file (item 2 of argv)) as \(exportFormat)
                        close doc saving no
                    on error message number code
                        try
                            close doc saving no
                        end try
                        if not wasRunning then quit
                        error message number code
                    end try
                    if not wasRunning then quit
                end tell
            end run
            """
        try await Self.run(script, arguments: [source.path, destination.path])
    }

    // osascript rather than NSAppleScript: Pages takes seconds to open a document, and
    // NSAppleScript would hold the main thread for all of it.
    private static func run(_ script: String, arguments: [String]) async throws {
        do {
            try await Subprocess.run(URL(filePath: "/usr/bin/osascript"), arguments: ["-e", script] + arguments)
        } catch let failure as Subprocess.Failure {
            throw error(from: failure.errorLines.joined(separator: "\n"))
        }
    }

    // osascript reports "<script>: execution error: <message> (<code>)".
    private static func error(from output: String) -> ConversionError {
        // errAEEventNotPermitted: the user turned down, or later revoked, Automation access to Pages.
        if output.contains("(-1743)") { return .automationDenied }
        var message = Substring(output)
        if let range = message.range(of: "execution error: ") { message = message[range.upperBound...] }
        if let range = message.range(of: #" \(-?\d+\)$"#, options: .regularExpression) { message = message[..<range.lowerBound] }
        return .pagesFailed(String(message))
    }
}
