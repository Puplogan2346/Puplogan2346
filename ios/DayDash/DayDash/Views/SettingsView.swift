import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var calendar: CalendarService

    @Environment(ClaudeService.self) private var claude
    @State private var name = ""
    @State private var apiKey = ""
    @State private var keySaved = false

    // Daily check-in reminder
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 8
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @State private var reminderTime = Date()
    @State private var notifDenied = false

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
                    Toggle("Daily check-in", isOn: $remindersEnabled)
                        .tint(Theme.terracotta)
                    if remindersEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A gentle daily nudge to check in with your day. Delivered locally on your device.")
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
            .onAppear {
                name = store.userName
                reminderTime = Calendar.current.date(
                    bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()
                ) ?? Date()
            }
            .onChange(of: remindersEnabled) { _, enabled in
                Task {
                    if enabled {
                        let granted = await NotificationManager.requestAuthorization()
                        if granted {
                            NotificationManager.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
                            Haptics.success()
                        } else {
                            remindersEnabled = false
                            notifDenied = true
                        }
                    } else {
                        NotificationManager.cancelDailyReminder()
                    }
                }
            }
            .onChange(of: reminderTime) { _, newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = comps.hour ?? 8
                reminderMinute = comps.minute ?? 0
                if remindersEnabled {
                    NotificationManager.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
                }
            }
            .alert("Key saved", isPresented: $keySaved) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("AI features are ready to go. ✨")
            }
            .alert("Notifications are off", isPresented: $notifDenied) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Enable notifications for DayDash in iOS Settings to get your daily check-in.")
            }
        }
    }

    private func save() {
        store.setUserName(name)
    }
}
