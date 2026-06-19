import Foundation
import UserNotifications

/// A single, gentle daily check-in notification. Local-only — no entitlement or server needed.
enum NotificationManager {
    static let dailyID = "daydash.daily.checkin"

    /// Ask for permission. Returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedule (or reschedule) the repeating daily reminder at the given time.
    static func scheduleDailyReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])

        let content = UNMutableNotificationContent()
        content.title = "DayDash"
        content.body = body(for: hour)
        content.sound = .default

        var when = DateComponents()
        when.hour = hour
        when.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        let request = UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyID])
    }

    /// A calm, time-appropriate nudge.
    private static func body(for hour: Int) -> String {
        switch hour {
        case 5..<12:  return "Good morning ☀️ Pick your one thing for today."
        case 12..<17: return "Afternoon check-in — what's the next small step?"
        case 17..<22: return "Evening reset. Anything to close out or jot down?"
        default:      return "A quiet moment — want to plan tomorrow?"
        }
    }
}
