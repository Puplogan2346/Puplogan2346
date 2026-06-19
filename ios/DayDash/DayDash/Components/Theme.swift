import SwiftUI

/// Visual design tokens. Calm, warm, high-contrast — and easy to read at a glance,
/// which matters for an ADHD-friendly app.
enum Theme {
    static let corner: CGFloat = 20

    /// Time-of-day greeting used across the app.
    static func greeting(for date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello, night owl"
        }
    }

    /// A short, rotating bit of encouragement.
    static var encouragement: String {
        [
            "One thing at a time. You've got this.",
            "Small steps still move you forward.",
            "Progress over perfection today.",
            "Pick the next tiny action — that's enough.",
            "Showing up is the hard part. Nice work."
        ].randomElement() ?? "You've got this."
    }
}

/// Card container used everywhere on the dashboard.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }
}

extension Color {
    /// Build a Color from a "#RRGGBB" hex string (used for calendar colors).
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
