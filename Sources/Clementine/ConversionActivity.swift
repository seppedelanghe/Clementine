import Foundation
import Observation

@MainActor
@Observable
final class ConversionActivity {
    // Conversions that finish within this never appear, so quick ones cause no flicker.
    private static let revealDelay = Duration.seconds(2)

    struct Job: Identifiable {
        let id = UUID()
        let files: [URL]
        let format: OutputFormat
        var fileIndex = 0
        var fileFraction = 0.0
        var isRevealed = false

        var fraction: Double { (Double(fileIndex) + fileFraction) / Double(files.count) }
    }

    private(set) var jobs: [Job] = []

    var visibleJobs: [Job] { jobs.filter(\.isRevealed) }

    // Average over the visible jobs; nil when nothing has run long enough to show.
    var fraction: Double? {
        let visible = visibleJobs
        guard !visible.isEmpty else { return nil }
        return visible.map(\.fraction).reduce(0, +) / Double(visible.count)
    }

    func begin(_ files: [URL], to format: OutputFormat) -> Job.ID {
        assert(!files.isEmpty)
        let job = Job(files: files, format: format)
        jobs.append(job)
        Task { [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            self?.reveal(job.id)
        }
        return job.id
    }

    // Updates can arrive after end(_:) because they hop to the main actor separately; those are dropped.
    func update(_ id: Job.ID, fileIndex: Int, fileFraction: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].fileIndex = fileIndex
        jobs[index].fileFraction = fileFraction
    }

    func end(_ id: Job.ID) {
        jobs.removeAll { $0.id == id }
    }

    private func reveal(_ id: Job.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].isRevealed = true
    }
}
