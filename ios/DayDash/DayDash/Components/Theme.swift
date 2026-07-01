import SwiftUI

/// The DayDash design system. Warm, soft, and tactile — tuned to feel like a
/// first-party Apple app: SF Rounded type, depth via material + shadow, and a
/// living background that shifts with the time of day.
enum Theme {
    static let corner: CGFloat = 24
    static let cardSpacing: CGFloat = 14

    // MARK: Palette (matches the warm "sunrise" app icon)

    static let peach = Color(red: 0.95, green: 0.65, blue: 0.49)
    static let terracotta = Color(red: 0.71, green: 0.34, blue: 0.29)
    static let amber = Color(red: 0.96, green: 0.74, blue: 0.42)
    static let dusk = Color(red: 0.45, green: 0.33, blue: 0.50)
    static let night = Color(red: 0.16, green: 0.17, blue: 0.30)

    // MARK: Type — SF Rounded everywhere for a friendly, premium feel

    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    // MARK: Time-of-day theming

    enum Daypart {
        case morning, afternoon, evening, night

        static func current(_ date: Date = Date()) -> Daypart {
            switch Calendar.current.component(.hour, from: date) {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<22: return .evening
            default: return .night
            }
        }

        /// Soft gradient for the dashboard hero background.
        var gradient: [Color] {
            switch self {
            case .morning:   return [Theme.peach.opacity(0.55), Theme.amber.opacity(0.30)]
            case .afternoon: return [Theme.amber.opacity(0.45), Theme.peach.opacity(0.28)]
            case .evening:   return [Theme.terracotta.opacity(0.50), Theme.dusk.opacity(0.35)]
            case .night:     return [Theme.dusk.opacity(0.55), Theme.night.opacity(0.55)]
            }
        }

        var greeting: String {
            switch self {
            case .morning: return "Good morning"
            case .afternoon: return "Good afternoon"
            case .evening: return "Good evening"
            case .night: return "Hello, night owl"
            }
        }
    }

    static func greeting(for date: Date = Date()) -> String { Daypart.current(date).greeting }

    /// A short, rotating bit of encouragement.
    static var encouragement: String {
        [
            "One thing at a time. You've got this.",
            "Small steps still move you forward.",
            "Progress over perfection today.",
            "Pick the next tiny action — that's enough.",
            "Showing up is the hard part. Nice work.",
            "Breathe. The list can wait a beat."
        ].randomElement() ?? "You've got this."
    }
}

// MARK: - Living time-of-day background

/// A soft, slowly-breathing gradient backdrop. Respects Reduce Motion.
struct TimeOfDayBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    var daypart: Theme.Daypart = .current()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: daypart.gradient,
                           startPoint: animate ? .topLeading : .top,
                           endPoint: animate ? .bottom : .bottomTrailing)
                .ignoresSafeArea()
                .opacity(0.9)
                .blur(radius: 0.5)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Glass card

/// A frosted, layered card with a soft shadow and hairline border — the core surface.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Interaction

/// Gentle scale + opacity on press. Makes every tappable surface feel alive.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Color from hex (calendar colors)

extension Color {
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
