# DayDash — START HERE (run & test guide)

Everything you need to build, run, and test DayDash — no chat required. For architecture and
"continue the project" info, see `HANDOVER.md`.

- **Repo:** `puplogan2346/puplogan2346`  ·  **Branch:** `claude/iphone-app-xcode-mac-a6xjjw`  ·  **PR:** #17
- **Project:** `ios/DayDash/DayDash.xcodeproj`  ·  **Requires:** Xcode 16+, iOS 17+

---

## 0) One-time prerequisites
1. A **Mac**.
2. **Xcode 16+** from the Mac App Store (large download; open it once after installing).

---

## 1) Get the code onto your Mac
Open **Terminal** and paste:
```bash
git clone https://github.com/puplogan2346/puplogan2346.git
cd puplogan2346
git checkout claude/iphone-app-xcode-mac-a6xjjw
open ios/DayDash/DayDash.xcodeproj
```
*(GUI alternative: GitHub Desktop → clone `puplogan2346/puplogan2346` → switch branch to
`claude/iphone-app-xcode-mac-a6xjjw` → open the `.xcodeproj`.)*

---

## 2) FASTEST TEST — iOS Simulator (no Apple account, no signing)
1. In Xcode's top toolbar, pick an **iPhone simulator** (e.g. "iPhone 16") in the device dropdown.
2. Press **▶︎ Run** (**⌘R**). First build takes a minute.
3. The Simulator launches and **DayDash opens**. It works fully offline with sample data.

Try: add tasks, set a "focus," complete habits, use Brain Dump.

---

## 3) Run on your REAL iPhone (free Apple ID is fine)
Your iPhone must be on **iOS 17+**.

1. **Connect & trust:** plug the iPhone into the Mac; on the phone tap **Trust This Computer**.
2. **Add Apple ID:** Xcode menu → **Xcode ▸ Settings ▸ Accounts ▸ "+" ▸ Apple ID** → sign in
   (creates a free "Personal Team").
3. **Signing:** click the blue **DayDash** project → **DayDash** target → **Signing &
   Capabilities** → check **Automatically manage signing** → set **Team** to your name.
4. **Fix the bundle id** if it errors: change `co.daydash.app` → something unique like
   **`com.yourname.daydash`**.
5. **Developer Mode (first time):** on the iPhone, **Settings ▸ Privacy & Security ▸ Developer
   Mode ▸ On**, then restart the phone.
6. **Run:** pick your iPhone in Xcode's device dropdown → **▶︎ Run**.
7. **Trust the app:** first run fails with "untrusted developer" — on the phone go to
   **Settings ▸ General ▸ VPN & Device Management** → tap your Apple ID → **Trust**.
8. Press **▶︎ Run** again → **DayDash launches on your iPhone.** 🎉

> **Free-account caveat:** apps signed with a free Apple ID stop opening after ~7 days. Just
> plug in and Run from Xcode again to refresh. A paid ($99/yr) Apple Developer account removes
> this and is required for the App Store.

---

## 4) Turn on the AI (the centerpiece)
1. Get a key at **console.anthropic.com** (Settings → API Keys).
2. In the app: **Today tab → profile icon (top-left) → Claude AI → paste key → Save**.
3. Open the **Assistant** tab and send a message (it **streams** in). Tap **✨** on Today for a
   streamed **Daily Briefing**.

Your key is stored in the iOS Keychain and only sent to api.anthropic.com. Everything except
the AI works with no key.

---

## 5) The two "connected" features
- **Calendar:** tap *Connect my calendar* on Today → approve. In the **Simulator** the calendar
  is empty (add an event via the Simulator's Calendar app to test); on a **real device** your
  actual events appear.
- **Daily check-in notification:** Settings → toggle **Daily check-in** → pick a time → approve.

---

## 6) Home Screen widget (already built in)
The **`DayWidget`** target is already wired into the project. After running the app once:
long-press the Home Screen → **+** → search **DayDash** → add the **Today** widget (small or medium).

It shows placeholder data until you flip on data sharing: in Xcode, select the **DayDash**
target → **Signing & Capabilities** → **+ Capability** → **App Groups** → add
**`group.co.daydash.app`**; then do the same on the **DayWidget** target. Re-run → the widget
shows your real focus + progress.

---

## Troubleshooting
- **Build errors (red):** copy the exact error text — that's the thing to bring back to a chat.
- **"Bundle identifier is not available":** make the bundle id unique (step 3.4).
- **iPhone not showing in device list:** unlock it, tap Trust, make sure the cable is data-capable.
- **"Untrusted Developer" on launch:** step 3.7 (trust the profile on the phone).
- **App won't open after a week:** free-account 7-day expiry — re-run from Xcode.
- **Xcode won't open the project:** you need **Xcode 16+** (the project format is new).

---

## How to continue the project efficiently (save usage)
- All code is on the branch + PR #17; this guide and `HANDOVER.md` capture the state.
- For a **fresh chat**, paste the kickoff block from `HANDOVER.md` (or just: *"Read
  ios/HANDOVER.md in puplogan2346/puplogan2346 branch claude/iphone-app-xcode-mac-a6xjjw and
  help me with X"*).
- Bring **specific build errors** rather than general questions — fastest, lowest-usage path.
