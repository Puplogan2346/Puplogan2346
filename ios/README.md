# DayDash — your day, in one calm place 📱

A native **SwiftUI iPhone app**: an ADHD-friendly daily dashboard that pulls your
day together in one place and has Claude AI built in. This is the native iOS
counterpart to the web Workday Checklist in the repo root.

## What it does

- **Today dashboard** — a calm home screen with a time-of-day greeting, a progress
  ring, your *one thing to focus on*, today's calendar events, habits at a glance,
  and quick task capture.
- **Tasks** — add, complete, and pick **one** task to focus on (so you're not
  juggling everything at once). Satisfying haptics when you finish something.
- **Habits** — tap to mark done, build 🔥 streaks.
- **Brain Dump** — a frictionless place to offload thoughts, ideas, and worries.
- **Assistant** — chat with **Claude** about your day (replies **stream in live**,
  token-by-token); it knows your tasks, focus, and habits and recommends *one* next action.
- **Daily Briefing** — one tap (✨) for an AI-written, encouraging plan for the day (also streamed).
- **Daily check-in** — an optional gentle **local notification** at a time you choose.
- **Home Screen widget** — small/medium widget showing your focus + progress
  (wired as the `DayWidget` target; shows live data once the App Group is enabled on both targets).
- **Momentum** — a 7-day chart of tasks finished, right on Today (Swift Charts).
- **Weekly habit dots** — each habit shows its last 7 days at a glance.
- **Brain Dump → Task** — swipe a captured thought right to promote it to a task.
- **Celebration** — finish every task for the day and get a confetti moment
  (respects Reduce Motion).
- **Welcome screen** — a one-screen first-run hello that asks your name.
- **Connections** — connects to your **Apple Calendar** on-device via EventKit.

## Open it on your Mac

1. Make sure you have **Xcode 16 or newer** (the project uses file-system
   synchronized groups and Swift Observation, targeting **iOS 17+**).
2. Open `ios/DayDash/DayDash.xcodeproj` in Xcode.
3. Select the **DayDash** scheme and an iPhone simulator (or your own device).
4. Press **⌘R** to build and run.

> Running on a *physical* iPhone: in **Signing & Capabilities**, pick your personal
> Apple ID team and change the bundle identifier (`co.daydash.app`) to something
> unique like `com.yourname.daydash`.

## Turning on the AI features

The Assistant and Daily Briefing call the Claude API directly.

1. Get an API key at [console.anthropic.com](https://console.anthropic.com).
2. In the app: **Today tab → gear icon → Claude AI → paste your key → Save**.
3. The key is stored in the **iOS Keychain** and only ever sent to
   `api.anthropic.com`. It's never written to disk in plain text or committed.

The app uses the `claude-opus-4-8` model via `POST /v1/messages`. Everything else
(tasks, habits, notes) works fully offline with no key.

> **Security note for a shipping app:** putting an API key on-device is fine for a
> personal starter, but for the App Store you'd route these calls through your own
> small backend so the key never lives on the phone. The AI layer is isolated in
> `Services/ClaudeService.swift`, so swapping in a backend URL later is a small change.

## Project layout

```
ios/DayDash/
  DayDash.xcodeproj/            Xcode project (open this)
  DayDash/
    DayDashApp.swift            App entry point
    Models/
      Models.swift              TaskItem, Habit, Note, DayEvent, ChatMessage
      AppStore.swift            @Observable store + JSON persistence
    Services/
      Keychain.swift            Secure API-key storage
      CalendarService.swift     EventKit (today's events)
      ClaudeService.swift       Claude API client (raw HTTPS)
    Views/
      RootView.swift            Tab bar
      TodayView.swift           The dashboard
      TasksView.swift, HabitsView.swift, BrainDumpView.swift
      AssistantView.swift       Claude chat
      BriefingView.swift        AI daily briefing
      SettingsView.swift        Name, connections, API key
    Components/
      Theme.swift, ProgressRing.swift, Haptics.swift
    Assets.xcassets/            App icon + accent color
```

## Design

DayDash is tuned to feel like a first-party Apple app:

- **SF Rounded** typography throughout, warm "sunrise" palette.
- A **living time-of-day background** that shifts (morning → night) and gently breathes
  (respects Reduce Motion).
- **Material/glass cards** with soft depth, a gradient + glowing **progress ring**, and
  animated numeric counts.
- **Spring motion** and **SF Symbol effects** (bounce on completion), plus layered
  **haptics** so finishing things feels good.
- A custom app icon (`Assets.xcassets/AppIcon.appiconset`).

## Roadmap ideas

- More account connections (Apple Reminders, Health, Gmail/Calendar via OAuth).
- Lock Screen / StandBy widgets and an interactive "complete focus task" widget button.
- Richer "plan my day" AI tools and tool-use (e.g. let the assistant add tasks for you).
