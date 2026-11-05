import Foundation
import UserNotifications

/// A local notification for when a limit that was running low refills.
///
/// Scheduled for the reset time itself rather than posted when it is noticed, so it arrives on time
/// with the app closed. Every fresh reading replaces what was scheduled for that assistant: a window
/// that resets early, or a new one that starts, moves the notification with it.
public enum AIUsageNotifications {

    /// Windows less spent than this are not worth interrupting for when they refill.
    static let threshold = 0.5

    private static let identifierPrefix = "aiusage.reset."

    public static var isEnabled: Bool {
        AIUsageKit.defaults?.bool(forKey: AIUsageDefaultsKey.notifiesOnReset) ?? false
    }

    /// Asks for permission to notify, if it has not been asked yet. Returns whether notifications
    /// are allowed afterwards.
    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces this reading's assistant's pending notifications with one per well-spent window.
    static func schedule(_ usage: AIUsage) async {
        guard isEnabled, !AIUsageKit.isScreenshotRun else { return }

        await cancel(usage.assistant)

        let windows: [(id: String, title: String, limit: AIUsageLimit)] =
            [AIUsageWindow.fiveHour, .week].compactMap { window in
                usage[window].map { (String(describing: window), window.title, $0) }
            } + usage.extras.map { ($0.id, $0.name, $0.limit) }

        let center = UNUserNotificationCenter.current()
        for window in windows where window.limit.used >= threshold {
            guard let resetsAt = window.limit.resetsAt, resetsAt.timeIntervalSinceNow > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(usage.assistant.name) Limit Reset", bundle: #bundle)
            content.body = String(localized: "Your \(window.title) limit has reset.", bundle: #bundle)
            content.sound = .default
            content.threadIdentifier = usage.assistant.rawValue

            let request = UNNotificationRequest(
                identifier: identifier(usage.assistant, window.id),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: resetsAt.timeIntervalSinceNow, repeats: false))
            try? await center.add(request)
        }
    }

    /// Drops what is pending for one assistant.
    static func cancel(_ assistant: AIAssistant) async {
        let center = UNUserNotificationCenter.current()
        let prefix = identifierPrefix + assistant.rawValue + "."
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    /// Drops everything pending, for when the reader turns notifications off.
    public static func cancelAll() async {
        for assistant in AIAssistant.allCases {
            await cancel(assistant)
        }
    }

    /// Schedules from the last readings, for when the reader turns notifications on.
    public static func scheduleCached() async {
        for usage in AIUsageCache.all() {
            await schedule(usage)
        }
    }

    private static func identifier(_ assistant: AIAssistant, _ window: String) -> String {
        identifierPrefix + assistant.rawValue + "." + window
    }
}
