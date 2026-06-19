import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var calendar: CalendarService

    @State private var claude = ClaudeService()
    @State private var name = ""
    @State private var apiKey = ""
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "sun.max.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [Theme.peach, Theme.terracotta],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DayDash").font(Theme.rounded(.headline))
                            Text("Your day, in one calm place.")
                                .font(Theme.rounded(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("You") {
                    TextField("First name", text: $name)
                        .font(Theme.rounded(.body))
                        .textInputAutocapitalization(.words)
                }

                Section {
                    switch calendar.access {
                    case .granted:
                        Label("Calendar connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .denied:
                        Label("Calendar access denied", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Enable it in iOS Settings › DayDash › Calendars.")
                            .font(Theme.rounded(.footnote)).foregroundStyle(.secondary)
                    case .unknown:
                        Button {
                            Haptics.tap()
                            Task { await calendar.requestAccessAndLoad() }
                        } label: {
                            Label("Connect Calendar", systemImage: "calendar.badge.plus")
                        }
                        .tint(Theme.terracotta)
                    }
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Your Apple Calendar is read on-device to show today's events. More connections (Reminders, Health, email) are on the roadmap.")
                }

                Section {
                    SecureField(claude.hasAPIKey ? "•••• stored securely" : "sk-ant-…", text: $apiKey)
                        .font(Theme.rounded(.body))
                    Button("Save key") {
                        claude.setAPIKey(apiKey)
                        apiKey = ""
                        keySaved = true
                        Haptics.success()
                    }
                    .tint(Theme.terracotta)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if claude.hasAPIKey {
                        Button("Remove key", role: .destructive) {
                            claude.setAPIKey("")
                            keySaved = false
                        }
                    }
                } header: {
                    Text("Claude AI")
                } footer: {
                    Text("Powers the Assistant and Daily Briefing. Your key is stored in the iOS Keychain and only sent to api.anthropic.com. Get a key at console.anthropic.com.")
                }

                Section {
                    Link(destination: URL(string: "https://console.anthropic.com")!) {
                        Label("Anthropic Console", systemImage: "safari")
                    }
                } footer: {
                    Text("DayDash v1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear { name = store.userName }
            .alert("Key saved", isPresented: $keySaved) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("AI features are ready to go. ✨")
            }
        }
    }

    private func save() {
        store.setUserName(name)
    }
}
