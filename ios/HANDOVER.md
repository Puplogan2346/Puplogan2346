# DayDash — Handover / Continuation Guide

This doc lets a fresh chat (or you) pick up exactly where we left off. DayDash is a native
SwiftUI iPhone app: an ADHD-friendly daily dashboard with Claude AI built in.

---

## 📍 Where we are right now (frontier)

- **All code + docs are committed and pushed** to branch `claude/iphone-app-xcode-mac-a6xjjw`
  (draft PR #17). Nothing is local-only. Working tree is clean.
- **Built so far:** full app (Today, Tasks, Habits, Brain Dump, Assistant), premium design
  pass, **streaming** Claude replies, **daily notification**, Apple Calendar integration,
  **widget code ready to wire**, and the run/test guides (`START-HERE.md`).
- **NOT done yet:** the app has **not been compiled in Xcode** (built in a Linux env). The
  widget target is **not** wired into the Xcode project yet.
- **The next action:** open `ios/DayDash/DayDash.xcodeproj` in **Xcode 16+**, press **⌘B**,
  and fix any compiler errors. See `START-HERE.md` for run/test steps (Simulator + iPhone).
- **To run/test:** read `START-HERE.md`. **To wire the widget:** read `DayDashWidget-SETUP.md`.

When you finish a chunk of work, update this section so the frontier stays accurate.

---


## Where everything lives

- **Repo:** `puplogan2346/puplogan2346`
- **Branch:** `claude/iphone-app-xcode-mac-a6xjjw`
- **Pull request:** **#17** (draft) — https://github.com/Puplogan2346/Puplogan2346/pull/17
- **App path:** `ios/DayDash/` — open **`ios/DayDash/DayDash.xcodeproj`** in Xcode
- **Requires Xcode 16+** (the project uses file-system synchronized groups, `objectVersion 77`)
  and targets **iOS 17.0+**.

The repo root is a separate, pre-existing **web** app (Workday Checklist). The iOS app is
self-contained under `ios/` and does not touch it. The CI `test` job is the web app's and
stays green regardless of iOS changes.

---

## Current status

✅ Built across four rounds: scaffold → premium design pass → streaming + notifications +
widget prep → pre-Xcode review. **Not yet compiled in Xcode** (development happened in a
Linux environment with no Xcode/macOS). Code was written against iOS 17 APIs and read
carefully, but the first Xcode build is the real test.

**The #1 next action: open in Xcode and do ⌘B, then fix any compiler errors.**

---

## Architecture (all under `ios/DayDash/DayDash/`)

| File | Responsibility |
|---|---|
| `DayDashApp.swift` | `@main`; creates the shared `AppStore`, injects via `.environment`. |
| `Models/Models.swift` | `TaskItem`, `Habit` (streak logic), `Note`, `DayEvent`, `ChatMessage`. Codable. |
| `Models/AppStore.swift` | `@Observable` single source of truth. All mutations go through methods (no `didSet` — it doesn't compose with `@Observable`). Persists arrays as JSON in Application Support. Calls `syncWidget()` after task/habit/focus changes. |
| `Shared/SharedStore.swift` | App-Group-aware `WidgetSnapshot` read/write; safe fallback to app container so the app works before the App Group is enabled. `AppGroup.id = "group.co.daydash.app"`. |
| `Services/ClaudeService.swift` | Claude API over raw HTTPS (`POST /v1/messages`, model **`claude-opus-4-8`**). `streamText(...)` = SSE streaming (preferred); `send(...)` = non-streaming fallback. Always checks `stop_reason == "refusal"`. |
| `Services/CalendarService.swift` | EventKit; requests full calendar access (iOS 17 `requestFullAccessToEvents`), loads today's events. |
| `Services/NotificationManager.swift` | Local daily check-in notification (schedule/cancel/auth). |
| `Services/Keychain.swift` | Stores the Claude API key in the iOS Keychain. |
| `Components/Theme.swift` | Design system: SF Rounded fonts, warm palette, `Daypart` time-of-day theming, `TimeOfDayBackground`, glass `Card`, `PressableStyle`, `Color(hex:)`. |
| `Components/ProgressRing.swift` | Gradient/glow progress ring with animated numeric label. |
| `Components/Haptics.swift` | tap / soft / selection / success feedback. |
| `Views/RootView.swift` | TabView (Today, Tasks, Habits, Brain Dump, Assistant). |
| `Views/TodayView.swift` | Dashboard: hero header, progress card, focus hero, calendar, habit chips, quick add. |
| `Views/TasksView.swift` | Tasks list, complete + single "focus" toggle, symbol effects. |
| `Views/HabitsView.swift` | Habits + streaks, emoji picker on add. |
| `Views/BrainDumpView.swift` | Quick note capture. |
| `Views/AssistantView.swift` | Claude chat; replies **stream token-by-token**. |
| `Views/BriefingView.swift` | One-tap AI daily briefing (also streamed). |
| `Views/SettingsView.swift` | Name, calendar connect, **daily reminder** toggle + time, API key entry. |

**Widget (not yet in an Xcode target):** `ios/DayDash/DayDashWidget/` — `DayDashWidget.swift`,
`DayDashWidgetBundle.swift`. Intentionally a sibling of the app's synchronized group so the
app target does **not** compile it. Wire it per `ios/DayDashWidget-SETUP.md`.

---

## Features done

- Today dashboard, Tasks (+ single-focus mode), Habits (+ streaks), Brain Dump.
- Apple Calendar integration (EventKit, on-device).
- Claude **Assistant chat** + **Daily Briefing**, both **streaming** (SSE).
- **Local daily check-in** notification (Settings toggle + time picker).
- Premium design: SF Rounded type, time-of-day living gradient, glass cards, gradient/glow
  progress ring, spring motion, SF Symbol effects, layered haptics, custom app icon.
- Home Screen **widget** code (small + medium) — ready to wire.

---

## Exact next steps in Xcode (do these in order)

1. **Open** `ios/DayDash/DayDash.xcodeproj` (Xcode 16+). Press **⌘B**. Fix any errors.
   - If errors appear, paste them into a new chat (see kickoff block below).
2. **Run** on a simulator (⌘R). The app works fully offline (sample tasks/habits seeded).
3. **API key (optional but core):** Today tab → profile icon → Claude AI → paste a key from
   console.anthropic.com → Save. Then try the Assistant and the ✨ briefing (watch it stream).
4. **Calendar:** tap "Connect my calendar" on Today; approve the prompt.
5. **Reminders:** Settings → Daily check-in → toggle on, pick a time.
6. **Run on a physical iPhone:** target → Signing & Capabilities → select your personal team;
   change the bundle id `co.daydash.app` → e.g. `com.yourname.daydash`.
7. **Home Screen widget:** follow `ios/DayDashWidget-SETUP.md` (≈5 min: add Widget Extension
   target, add the 3 files to target membership, enable App Group `group.co.daydash.app` on
   **both** targets). If you changed the bundle id, also update `AppGroup.id` in
   `Shared/SharedStore.swift`.

---

## Things to watch (most-likely friction points)

- **Xcode 16 required** — `objectVersion 77` + synchronized groups won't open in Xcode 15.
- **App icon** is a real generated PNG (`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`).
- **API key on device:** fine for personal use; for the App Store, proxy Claude calls through
  a backend so the key isn't on the phone. The only file to change is `ClaudeService.swift`
  (point it at your endpoint).
- **Widget data sharing needs the App Group enabled on both targets** or the widget shows
  placeholder data (the app itself still works via the fallback container).
- **No automated UI/unit tests yet** for the iOS app.
- Streaming uses raw SSE parsing (no Swift SDK exists). If Anthropic changes the event shape,
  the parser is in `ClaudeService.streamText`.

## Conventions

- Develop on branch `claude/iphone-app-xcode-mac-a6xjjw`; push there; PR #17 is the draft.
- Claude model id is **`claude-opus-4-8`** (don't downgrade without reason).
- Commit trailers used in this project:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KF1svUYzgw68nVhyvH8xU5
  ```

---

## Kickoff block — paste this into a new chat

> I'm continuing work on **DayDash**, a SwiftUI iPhone app in the repo
> `puplogan2346/puplogan2346` on branch `claude/iphone-app-xcode-mac-a6xjjw` (draft PR #17).
> The app is under `ios/DayDash/`. Please read `ios/HANDOVER.md` first — it explains the
> architecture and current state. It's been written but not yet compiled in Xcode.
>
> [If you have build errors:] Here are the Xcode build errors from ⌘B: `<paste errors>`
>
> [Or pick a task:] Help me (a) get a clean build, (b) wire the Home Screen widget target per
> `ios/DayDashWidget-SETUP.md`, or (c) add <feature>.

---

## Ideas not yet built

- Interactive widget button to complete the focus task (AppIntent).
- Lock Screen / StandBy widgets.
- Let the Assistant *add tasks* via tool use.
- More connections (Reminders, Health, Gmail/Calendar OAuth).
- Unit/UI tests.
