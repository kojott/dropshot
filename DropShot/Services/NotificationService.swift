import Foundation
import AppKit
import UserNotifications

// MARK: - Notification Constants

private enum NotificationConstants {
    static let uploadCategoryId = "UPLOAD_RESULT"
    static let batchCategoryId = "BATCH_UPLOAD_RESULT"
    static let infoCategoryId = "INFO"
    static let failureCategoryId = "UPLOAD_FAILURE"

    static let copyPathActionId = "COPY_PATH_ACTION"
    static let openPreferencesActionId = "OPEN_PREFERENCES_ACTION"
    static let retryActionId = "RETRY_ACTION"

    static let clipboardTextKey = "clipboardText"
}

// MARK: - Notification Service

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        setupNotificationCategories()
    }

    // MARK: - Permission

    /// Requests authorization to display notifications. Safe to call multiple times;
    /// the system only prompts the user once.
    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                // The user declined notifications. The app should still function,
                // so we log but do not throw.
                print("[NotificationService] User declined notification permission.")
            }
        } catch {
            print("[NotificationService] Failed to request notification permission: \(error.localizedDescription)")
        }
    }

    // MARK: - Upload Success

    /// Shows a notification for a single successful upload. Tapping "Copy Path"
    /// places `clipboardText` on the pasteboard.
    func showUploadSuccess(filename: String, clipboardText: String) {
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body = "\(filename) uploaded successfully."
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.uploadCategoryId
        content.userInfo = [NotificationConstants.clipboardTextKey: clipboardText]

        let request = UNNotificationRequest(
            identifier: "upload-success-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule success notification: \(error.localizedDescription)")
            }
        }
    }

    /// Shows a notification for a batch of successful uploads.
    func showBatchUploadSuccess(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Batch Upload Complete"
        content.body = "\(count) file\(count == 1 ? "" : "s") uploaded successfully."
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.batchCategoryId

        let request = UNNotificationRequest(
            identifier: "batch-upload-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule batch notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Upload Failure

    /// Shows a notification when an upload fails, with guidance drawn from the error.
    func showUploadFailure(filename: String, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Upload Failed"
        content.body = "\(filename): \(error.localizedDescription)"
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = NotificationConstants.failureCategoryId

        let request = UNNotificationRequest(
            identifier: "upload-failure-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule failure notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Generic Info

    /// Shows a plain informational notification with no special actions.
    func showInfo(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.infoCategoryId

        let request = UNNotificationRequest(
            identifier: "info-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule info notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Categories & Actions

    /// Registers notification categories and their associated actions with the
    /// notification center. Called once during initialization.
    func setupNotificationCategories() {
        let copyPathAction = UNNotificationAction(
            identifier: NotificationConstants.copyPathActionId,
            title: "Copy Path",
            options: [.foreground]
        )

        let openPreferencesAction = UNNotificationAction(
            identifier: NotificationConstants.openPreferencesActionId,
            title: "Open Preferences",
            options: [.foreground]
        )

        let retryAction = UNNotificationAction(
            identifier: NotificationConstants.retryActionId,
            title: "Retry",
            options: [.foreground]
        )

        let uploadCategory = UNNotificationCategory(
            identifier: NotificationConstants.uploadCategoryId,
            actions: [copyPathAction, openPreferencesAction],
            intentIdentifiers: [],
            options: []
        )

        let batchCategory = UNNotificationCategory(
            identifier: NotificationConstants.batchCategoryId,
            actions: [openPreferencesAction],
            intentIdentifiers: [],
            options: []
        )

        let failureCategory = UNNotificationCategory(
            identifier: NotificationConstants.failureCategoryId,
            actions: [retryAction, openPreferencesAction],
            intentIdentifiers: [],
            options: []
        )

        let infoCategory = UNNotificationCategory(
            identifier: NotificationConstants.infoCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([uploadCategory, batchCategory, failureCategory, infoCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is delivered while the app is in the foreground.
    /// We allow banners to show even when the app is active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user interacts with a notification action.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case NotificationConstants.copyPathActionId:
            if let clipboardText = userInfo[NotificationConstants.clipboardTextKey] as? String {
                Task { @MainActor in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(clipboardText, forType: .string)
                }
            }

        case NotificationConstants.openPreferencesActionId:
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                // Post a notification that the main app can observe to open preferences.
                NotificationCenter.default.post(name: .dropShotOpenPreferences, object: nil)
            }

        case NotificationConstants.retryActionId:
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .dropShotRetryUpload, object: nil)
            }

        case UNNotificationDefaultActionIdentifier:
            // The user tapped the notification body itself.
            if let clipboardText = userInfo[NotificationConstants.clipboardTextKey] as? String {
                Task { @MainActor in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(clipboardText, forType: .string)
                }
            }

        default:
            break
        }

        completionHandler()
    }
}

// MARK: - App-Level Notification Names

extension Notification.Name {
    static let dropShotOpenPreferences = Notification.Name("com.dropshot.openPreferences")
    static let dropShotRetryUpload = Notification.Name("com.dropshot.retryUpload")
}
