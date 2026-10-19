import Foundation
import UserNotifications

enum FailureNotification {
    static func post(_ failures: [ConversionFailure], to format: OutputFormat) async throws {
        assert(!failures.isEmpty)
        if failures.count == 1 {
            try await deliver(
                title: "Couldn't convert \(failures[0].file.lastPathComponent) to \(format.title)",
                body: failures[0].error.localizedDescription
            )
        } else {
            try await deliver(
                title: "Couldn't convert \(failures.count) files to \(format.title)",
                body: failures
                    .map { "\($0.file.lastPathComponent): \($0.error.localizedDescription)" }
                    .joined(separator: "\n")
            )
        }
    }

    static func post(_ error: any Error, action: String) async throws {
        try await deliver(title: "\(action) failed", body: error.localizedDescription)
    }

    private static func deliver(title: String, body: String) async throws {
        let center = UNUserNotificationCenter.current()
        // Asked on the first failure rather than at launch; after that it returns the stored answer.
        guard try await center.requestAuthorization(options: [.alert]) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
