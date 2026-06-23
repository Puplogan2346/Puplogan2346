# DayDash — Adding the Unit Test target (≈2 min in Xcode)

The test code already exists under `ios/DayDash/DayDashTests/`:

- `ModelTests.swift` — pure value-type logic (`Habit.currentStreak`, `TaskItem.toggle`,
  `WidgetSnapshot.progress`, `Color(hex:)`, `DayKey`, `Theme.Daypart`).
- `AppStoreTests.swift` — `AppStore` mutations (add, focus-clearing on complete, and the
  filtered-list `deleteTasks(at:in:)` offset→id mapping). These are self-cleaning and safe to
  re-run.

It isn't wired into a test target yet, because a Unit Testing Bundle target can't be added
safely by hand-editing `project.pbxproj` outside Xcode (a single mistake there can stop the
project from opening). Xcode adds it in a couple of clicks, and — because the project uses
file-system-synchronized groups — the existing files are picked up automatically.

## Steps

1. Open `ios/DayDash/DayDash.xcodeproj` in **Xcode 16+**.
2. **File ▸ New ▸ Target… ▸ Unit Testing Bundle.**
   - Product Name: **`DayDashTests`** (must match the folder name so the synchronized group
     maps to it).
   - "Target to be Tested": **DayDash**.
   - Team/language defaults are fine; finish.
3. Xcode creates a `DayDashTests` group. If it generated a stub `DayDashTests.swift`, delete it
   (the real tests are `ModelTests.swift` / `AppStoreTests.swift`). Confirm both files show
   **Target Membership ▸ DayDashTests** in the File Inspector — with synchronized groups they
   should already be included.
4. The tests use `@testable import DayDash`, which needs **Enable Testability = YES** in the
   app target's Debug config — it already is in this project.
5. Press **⌘U** (Product ▸ Test). All tests should pass on a simulator.

## Notes

- `AppStoreTests` exercises real disk persistence (Application Support JSON). The tests use a
  `ZZTEST-` title prefix and clean up in `tearDown`, so they only assert about items they
  create and won't disturb your real data.
- If you later add a UI test target, repeat the same flow with a **UI Testing Bundle**.
