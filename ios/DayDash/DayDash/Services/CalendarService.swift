import Foundation
import EventKit
import Observation

/// Connects to the device's Calendar (a real "personal account" integration) via EventKit
/// and exposes today's events to the dashboard.
@Observable
final class CalendarService {
    enum Access: Equatable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var todayEvents: [DayEvent] = []

    private let store = EKEventStore()

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: access = .granted
        case .denied, .restricted: access = .denied
        default: access = .unknown
        }
    }

    /// Ask the user for calendar access, then load today's events on success.
    func requestAccessAndLoad() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .granted : .denied
            if granted { await loadToday() }
        } catch {
            access = .denied
        }
    }

    func loadToday() async {
        guard access == .granted else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .map { ek in
                DayEvent(
                    id: ek.eventIdentifier ?? UUID().uuidString,
                    title: ek.title ?? "(No title)",
                    start: ek.startDate ?? Date(),
                    end: ek.endDate ?? Date(),
                    isAllDay: ek.isAllDay,
                    calendarColorHex: ek.calendar?.cgColor.flatMap(Self.hex(from:))
                )
            }
        todayEvents = events
    }

    private static func hex(from color: CGColor) -> String? {
        guard let comps = color.components, comps.count >= 3 else { return nil }
        let r = Int(comps[0] * 255), g = Int(comps[1] * 255), b = Int(comps[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
