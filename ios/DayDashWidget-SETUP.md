# Adding the DayDash Home Screen widget (5 minutes in Xcode)

The widget's Swift code is already written in `ios/DayDash/DayDashWidget/`. It only needs to
be wired into a **Widget Extension target** with a shared **App Group**. This is a quick,
guided step — best done in Xcode because Xcode auto-provisions the App Group + signing
(doing it by hand in the project file risks breaking the app's code signing).

## 1. Create the widget target
1. In Xcode: **File ▸ New ▸ Target… ▸ Widget Extension**.
2. Name it **`DayDashWidget`**. Uncheck "Include Live Activity" and "Include Configuration
   App Intent" (we use a simple static widget). Finish, and **Activate** the scheme if asked.
3. Xcode generates a starter `DayDashWidget.swift` and a bundle file in a new group. **Delete
   those generated `.swift` files** (move to Trash) — we'll use the ones already in the repo.

## 2. Add the real source files to the widget target
1. In the Project navigator, select these files and open the **File Inspector** (right panel):
   - `DayDashWidget/DayDashWidget.swift`
   - `DayDashWidget/DayDashWidgetBundle.swift`
   - `DayDashWidget/CompleteFocusIntent.swift`  ← interactive "Mark done" button
   - `DayDash/Shared/SharedStore.swift`  ← shared with the app
2. Under **Target Membership**, make sure:
   - `DayDashWidget.swift`, `DayDashWidgetBundle.swift`, `CompleteFocusIntent.swift`
     → checked for **DayDashWidget only**
   - `SharedStore.swift` → checked for **BOTH** `DayDash` and `DayDashWidget`

   (If the new files aren't already in the project, drag the `DayDashWidget` folder into the
   project and add it to the `DayDashWidget` target.)

## 3. Enable the App Group on BOTH targets
This is what lets the app and widget share data.
1. Select the **DayDash** target ▸ **Signing & Capabilities** ▸ **+ Capability** ▸ **App Groups**.
2. Add the group **`group.co.daydash.app`** (must match `AppGroup.id` in `SharedStore.swift`).
3. Repeat for the **DayDashWidget** target — add the **same** group id.

> If you changed the app's bundle id earlier (e.g. `com.yourname.daydash`), pick any unique
> App Group id you like and update `AppGroup.id` in `SharedStore.swift` to match.

## 4. Run
- Build & run the app once (so it writes the first snapshot), then long-press the Home Screen
  ▸ **+** ▸ search **DayDash** ▸ add the **Today** widget (small or medium).
- The widget shows your greeting, focus task, task progress, and habits-done — and refreshes
  automatically whenever you change things in the app (via `WidgetCenter` reload).

## How it works
- The app writes a small `WidgetSnapshot` JSON into the shared App Group container on every
  change (`AppStore.syncWidget()` → `SharedStore.write`).
- The widget reads that snapshot in its `TimelineProvider`.
- Before the App Group is enabled, `SharedStore` falls back to the app's own container, so the
  **app keeps working** — the widget just shows placeholder data until step 3 is done.

## Interactive "Mark done" button
- When there's a focus task, the widget shows a tappable checkmark (small) / "Mark done"
  capsule (medium), backed by `CompleteFocusIntent` (an `AppIntent`).
- The widget can't reach the app's task list directly, so the intent queues a tiny command via
  `SharedStore.requestFocusCompletion()` and updates the snapshot optimistically for instant
  feedback. The app drains the command in `AppStore.applyPendingWidgetActions()` on launch and
  on returning to the foreground, completing the real task and clearing the focus.
- This round-trip needs the **App Group enabled on both targets** (step 3) — otherwise the two
  processes use separate fallback containers and the command can't cross over.
