# Consigliere — SPEC

A voice that lives in the MacBook notch. You type or say the name of a thing and it opens. You drag something onto the notch and it's saved. You click the notch when bored and it hands one saved thing back. After each action, an Italian voice says a short line. Nobody can see where the voice comes from.

Built for one person (Adi). Not for sale. Target machine: M1 Pro MacBook Pro (has a notch), arriving end of September 2026. **Until then nothing in the app target can be compiled or run.** This spec is written around that fact.

---

## 1. Hard rules

These override everything else in this file.

> **Version 2 (11 October 2026) changed rules 4, 5 and 7.** He may come out of the notch *silently* when a job is due, there is one small character, and unfinished jobs are "owed" (not a streak). The current rules are in `CLAUDE.md`; this spec is kept as the history of version 1.

1. **Action first, voice after.** The thing opens, then the line plays. Voice never delays an action.
2. **Under 1.5 seconds** from Enter (or key release) to the thing being open.
3. **No vocabulary.** The box is a search over the names of his things. No command words to memorise. Everything that isn't "open a thing" is a gesture or a hotkey, not a typed command.
4. **Never speaks unprompted.** Voice only plays in response to something he just did.
5. **No avatar, no character, no face.** The presence is the notch itself plus a blinking amber block cursor.
6. **No TV metaphors.** No channels, static, TV guide, "no signal". The look is amber phosphor text on black. That's all that survives from the CRT idea.
7. **No streaks, dashboards, review queues, check-ins, or screen watching.**

If a proposed feature breaks one of these, don't build it. Write it in `IDEAS.md` and move on.

---

## 2. The four gestures

| Gesture | What he does | What happens |
|---|---|---|
| **Type** | Hotkey → notch expands into a box → types `yt` → Enter | YouTube opens in Brave on the right profile. Notch collapses. Line plays. |
| **Talk** | Holds the talk key, says "youtube", releases | Same as Type, through the same matcher. |
| **Drop** | Drags a link, text, image or file onto the notch | It's saved to the stash. Short line plays. |
| **Pull** | Clicks the notch (or types `bored`) | One saved item opens. A small "another" button is visible for a few seconds; clicking it serves the next one. |

Plus one hotkey with no UI: **Save** — saves the front browser tab to the stash.

Designed for but NOT built in this sprint: **Idle** — the collapsed notch silently shows one tiny glanceable thing (a chord shape, a line of Python) from a deck he picks. Never speaks, never pops up.

---

## 3. Look

- Collapsed: invisible inside the notch. Optional 1 amber block `▮` beside it while listening.
- Expanded: black panel growing out of the notch. Amber text `#FFB000`, soft glow (`shadow` same colour, low radius). Monospaced font (SF Mono is fine; bundle VT323 only if licensing is clean).
- Input line: `> yt▮` with blinking block cursor. Below it, max 4 matches. Top match inverted (amber background, black text). Right side of each row shows where it opens, e.g. `BRAVE / PERSONAL`.
- After Enter: the line he speaks also shows as amber text for ~2s, then the notch collapses.
- On a screen with no notch: DynamicNotchKit's floating style at top centre.

---

## 4. Architecture

Two parts. The split exists so that as much as possible can be tested **without a Mac**.

### 4.1 `ConsigliereCore` — Swift package, Foundation only

No AppKit, no SwiftUI, no AVFoundation. Must build and pass `swift test` on Linux.

| Module | Job |
|---|---|
| `Catalog` | Loads the list of things he can open from config. |
| `Matcher` | Text in → ranked catalog entries out. |
| `Stash` | Saved items: add, serve, mark opened, persistence. |
| `Lines` | Picks which line to say (or none). |
| `Config` | Reads/writes `~/.consigliere/config.json`. Codable, with defaults. |
| `ActionPlan` | Turns a matched entry into a plain description of what to do (`.openURL(url, browser, profile)`, `.openApp(bundleID)`, `.openPath(path)`). Pure data. The app target executes it. |

### 4.2 `Consigliere` — macOS app target (SwiftUI + AppKit)

| Module | Job | Notes |
|---|---|---|
| `NotchController` | Expand / collapse / show line | Built on **DynamicNotchKit** (MIT). |
| `Hotkeys` | Global hotkeys incl. key-down AND key-up for hold-to-talk | Use `soffes/HotKey` or `sindresorhus/KeyboardShortcuts`. Read the library source to confirm key-up support. Do not guess the API. |
| `Executor` | Runs an `ActionPlan` | See 4.3. |
| `DropTarget` | Notch accepts dragged URLs, text, images, files | SwiftUI `onDrop`. Look at how NotchDrop / Boring Notch do their shelf. |
| `TabGrabber` | Front browser tab URL + title for the Save hotkey | AppleScript to Brave. Needs Automation permission. |
| `Ears` | Hold-to-talk speech → text | `SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`, `AVAudioEngine`. Start on key-down, finalise on key-up. Feed catalog names + aliases into `contextualStrings`. |
| `Mouth` | Plays the line | See 4.4. |

App settings: menu-bar-less agent app (`LSUIElement = true`), App Sandbox **off** (it launches processes and sends AppleScript). Info.plist needs `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSAppleEventsUsageDescription`.

Project file: **XcodeGen** (`project.yml`, plain text). Do not hand-write an `.xcodeproj`. On the Mac: `brew install xcodegen && xcodegen`.

### 4.3 Opening things

- **Site in Brave with a profile** — launch the binary directly, because `open -a ... --args` drops the args when Brave is already running:
  `"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" --profile-directory="<dir>" "<url>"`
  via `Process`. `<dir>` comes from config (real values found on day one, see DAY_ONE.md).
- **App** — `NSWorkspace.shared.openApplication` by bundle ID.
- **Folder / file** — `NSWorkspace.shared.open(URL)`.
- **Site search** — if the first token matches a site that has a `searchTemplate` and more words follow (`yt berserk amv`), open the search URL. This is not a command; it's typing a site name and then what you want.

### 4.4 The voice

Order of preference at runtime:

1. **Pre-made audio**: `Resources/lines/<lineID>.m4a` if it exists → `AVAudioPlayer`.
2. **Free fallback**: `AVSpeechSynthesizer` using an **Italian (`it-IT`) system voice reading the English text**. An Italian voice reading English produces a heavy Italian accent for free. Pick the best installed `it-IT` voice at launch; if none, use default voice.

Rules: play after the action fires; never overlap two lines (drop the new one); respect `voice.enabled` and `voice.frequency` (0.0–1.0 chance of speaking per action; the amber text line always shows regardless). Mute toggle lives in a right-click menu on the notch.

---

## 5. Matching (`Matcher`)

1. Normalise: lowercase, strip spaces and punctuation (`you tube` → `youtube`).
2. Score each catalog entry across its `name` + `aliases`:
   exact > prefix > word-prefix > subsequence (`ytb` hits `youtube`) > small edit distance (for speech mishearings like `you to`).
3. Tie-break by usage count, then recency (store counts in a small `usage.json`).
4. Return top 4. Empty input returns the 4 most used.
5. Speech input goes through the same path, but if the top score is weak, do nothing and show `?` — never open a wrong thing on a bad guess.

Must be unit tested with a table of at least 60 cases, including speech-mangled inputs.

---

## 6. Stash (`Stash`)

File: `~/Library/Mobile Documents/com~apple~CloudDocs/Consigliere/stash.json` (iCloud Drive, so a phone Shortcut can append to it later). Falls back to `~/.consigliere/stash.json` if iCloud Drive is missing. Inject the path so tests use a temp dir.

Item: `id`, `kind` (url | text | file | image), `payload`, `title?`, `source` (drop | hotkey | phone), `savedAt`, `servedAt?`, `openedAt?`, `skippedCount`.

Serving rules:
- Never serve an item that has `openedAt`.
- Alternate between a **fresh** bucket (saved < 14 days ago) and an **old** bucket; random within the bucket; if one bucket is empty use the other.
- "Another" marks the current item skipped (`skippedCount += 1`, clears `openedAt`) and serves the next immediately. Items skipped 3+ times drop to the back.
- Empty stash → an `empty_stash` line. No guilt.
- Tolerate a malformed or half-synced file: never crash, never wipe. Write atomically.

Must be unit tested with fixtures and an injected clock + random source.

---

## 7. Lines (`Lines`)

File: `lines.json`. Around 200 lines total.

Categories: `open_site`, `open_app`, `open_path`, `saved`, `pulled`, `another`, `empty_stash`, `unknown`, `muted_on`, `muted_off`, plus per-target overrides (`target:youtube`, `target:steam`, `target:gmail`, …) which win over the generic category when present.

Writing rules:
- Register: affectionate Italian-American mob uncle. `"YouTube. Again. Mamma mia."` `"It's done. Don't ask how."`
- Max 8 words. Must be speakable in under 2.5 seconds.
- The joke is about the task or about Adi. Never about Italians.
- No line may give advice, ask a question, or comment on how long he's been doing something. (Rule 4 and 7.)
- Picker never repeats the last 5 lines used in a category.

---

## 8. Config

`~/.consigliere/config.json`. Created with sane defaults on first run. Adding a thing = adding one object to `catalog`:

```json
{
  "hotkeys": { "open": "opt+space", "talk": "right_opt", "save": "opt+s" },
  "brave": { "personalProfileDir": "Default", "workProfileDir": "Profile 1" },
  "voice": { "enabled": true, "frequency": 0.6 },
  "catalog": [
    { "name": "youtube", "aliases": ["yt"], "kind": "site",
      "target": "https://youtube.com", "profile": "personal",
      "searchTemplate": "https://www.youtube.com/results?search_query={q}" },
    { "name": "steam", "aliases": [], "kind": "app", "target": "com.valvesoftware.steam" },
    { "name": "downloads", "aliases": ["dl"], "kind": "path", "target": "~/Downloads" }
  ]
}
```

Seed the default catalog with: youtube, gmail, linkedin, whatsapp, github, claude, spotify, steam, vs code, downloads, desktop. Hotkey values above are placeholders; he'll choose on the Mac.

---

## 9. Rules for writing code that can't be run

The whole app target is being written blind. So:

1. **Never guess a third-party API.** Clone DynamicNotchKit and the hotkey library into `/reference`, read their source, and pin exact versions in `Package.swift` / `project.yml`.
2. Clone `TheBoredTeam/boring.notch` and `Lakr233/NotchDrop` into `/reference` to study how they handle the notch window, hover, and drag-and-drop. **Read for technique; do not paste their code.** Check each LICENSE file first and note it in `REFERENCES.md`.
3. Keep the app target thin. Any logic that can live in `ConsigliereCore` must live there.
4. Every assumption that could not be verified goes in `BLIND_SPOTS.md` with the file and line it affects. This is the debugging map for day one.
5. Try to install a Swift toolchain in the sandbox and actually run `swift test` for `ConsigliereCore`. If the sandbox blocks it, say so clearly in `BLIND_SPOTS.md` — do not claim tests pass.
6. Tests first for every Core module.

---

## 10. Files the sprint must produce

```
SPEC.md                      this file
Package.swift                ConsigliereCore + tests
Sources/ConsigliereCore/...
Tests/ConsigliereCoreTests/...
App/project.yml              XcodeGen
App/Consigliere/...            the blind app target
App/Consigliere/Resources/lines.json
BLIND_SPOTS.md               every unverified assumption
REFERENCES.md                libraries + reference repos + their licences
DAY_ONE.md                   exact steps for the first hour on the Mac
IDEAS.md                     parked features
```

`DAY_ONE.md` must include: install Xcode + Homebrew + xcodegen; how to find the real Brave profile directory names (`ls ~/Library/Application\ Support/BraveSoftware/Brave-Browser/`); generate + build; the permission prompts to expect (Microphone, Speech Recognition, Automation → Brave); how to check which `it-IT` voices are installed and download a better one in System Settings; a 10-item smoke test.

---

## 11. Sprint order (credits expire in under 24h)

Spend in this order. Stop adding features after step 5; spend what's left on step 6.

1. Repo skeleton + this spec committed.
2. `ConsigliereCore`: Config → Catalog → Matcher → Stash → Lines → ActionPlan. Tests first.
3. `lines.json`: generate ~300, cut to the best ~200 against the rules in section 7.
4. `/reference` clones + `REFERENCES.md`.
5. App target: NotchController → Hotkeys → Executor → Mouth → DropTarget → TabGrabber → Ears. `project.yml`, Info.plist.
6. **Review passes with a fresh session**: read the app target against the reference library source and hunt for compile errors, wrong signatures, main-actor/concurrency mistakes, missing entitlements. Update `BLIND_SPOTS.md`. Repeat until credits run out.
7. `DAY_ONE.md`.

---

## 12. Session prompts (paste one at a time into Claude Code)

**Session 1**
> Read SPEC.md fully. Do sprint steps 1 and 2 only. Tests first. Try to install a Swift toolchain and run `swift test`; if you can't, say so and record it in BLIND_SPOTS.md. Commit after each module.

**Session 2**
> Read SPEC.md section 7. Generate 300 candidate lines, then cut to the best 200 by the rules. Output `App/Consigliere/Resources/lines.json`. Show me 20 samples across categories before committing.

**Session 3**
> Read SPEC.md sections 4, 9, 10. Do sprint step 4, then step 5. Read library source in /reference before using any API. Log every unverified assumption in BLIND_SPOTS.md. Commit per module.

**Session 4 (repeat until credits are gone)**
> You are reviewing code that has never been compiled. Read App/ against the pinned library source in /reference and Apple's API conventions. Find anything that would fail to compile or crash on launch. Fix it, and update BLIND_SPOTS.md. Do not add features.

**Session 5**
> Write DAY_ONE.md per SPEC.md section 10.
