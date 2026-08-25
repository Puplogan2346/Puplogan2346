import SwiftUI

/// First-launch welcome: a warm hello, what the app does, and the user's name.
/// Kept to a single screen — no multi-page onboarding to wade through.
struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            TimeOfDayBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(
                        LinearGradient(colors: [Theme.peach, Theme.terracotta],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .shadow(color: Theme.terracotta.opacity(0.4), radius: 16, y: 8)

                Text("Welcome to DayDash")
                    .font(Theme.rounded(.largeTitle, weight: .bold))
                    .padding(.top, 22)
                Text("Your day, in one calm place.")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    pitchRow(icon: "scope", tint: Theme.terracotta,
                             title: "One thing at a time",
                             detail: "Pick a single focus so the list never overwhelms.")
                    pitchRow(icon: "flame.fill", tint: .orange,
                             title: "Streaks that stick",
                             detail: "Tap a habit, keep the fire going.")
                    pitchRow(icon: "sparkles", tint: Theme.dusk,
                             title: "An assistant that gets it",
                             detail: "Claude sees your day and suggests the next small step.")
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 28)

                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    TextField("What should I call you?", text: $name)
                        .font(Theme.rounded(.body))
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(finish)
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button(action: finish) {
                        Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Let's go" : "Let's go, \(name.trimmingCharacters(in: .whitespaces))")
                            .font(Theme.rounded(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .tint(Theme.terracotta)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled(false)
    }

    private func pitchRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rounded(.subheadline, weight: .semibold))
                Text(detail).font(Theme.rounded(.footnote)).foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.setUserName(trimmed) }
        Haptics.success()
        dismiss()
    }
}
