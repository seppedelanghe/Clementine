import Foundation
import UserNotifications

enum FailureNotification {
    static func post(_ failures: [ConversionFailure], to format: OutputFormat) async throws {
        assert(!failures.isEmpty)
        let center = UNUserNotificationCenter.current()
        // Asked on the first failure rather than at launch; after that it returns the stored answer.
        guard try await center.requestAuthorization(options: [.alert]) else { return }

        let content = UNMutableNotificationContent()
        if failures.count == 1 {
            content.title = "Couldn't convert \(failures[0].file.lastPathComponent) to \(format.title)"
            content.body = failures[0].error.localizedDescription
        } else {
            content.title = "Couldn't convert \(failures.count) files to \(format.title)"
            content.body = failures
                .map { "\($0.file.lastPathComponent): \($0.error.localizedDescription)" }
                .joined(separator: "\n")
        }
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
