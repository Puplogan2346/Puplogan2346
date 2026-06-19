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
                Section("You") {
                    TextField("First name", text: $name)
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
                            .font(.footnote).foregroundStyle(.secondary)
                    case .unknown:
                        Button {
                            Task { await calendar.requestAccessAndLoad() }
                        } label: {
                            Label("Connect Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Your Apple Calendar is read on-device to show today's events. More connections (Reminders, Health, email) are on the roadmap.")
                }

                Section {
                    SecureField(claude.hasAPIKey ? "•••• stored securely" : "sk-ant-…", text: $apiKey)
                    Button("Save key") {
                        claude.setAPIKey(apiKey)
                        apiKey = ""
                        keySaved = true
                    }
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
                    Link("Anthropic Console", destination: URL(string: "https://console.anthropic.com")!)
                } header: {
                    Text("About")
                } footer: {
                    Text("DayDash — your day, in one calm place.")
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
                Text("AI features are ready to go.")
            }
        }
    }

    private func save() {
        store.setUserName(name)
    }
}
