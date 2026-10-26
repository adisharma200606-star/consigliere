# Blind spots

Everything in here is a guess that could not be checked without a Mac. Each one says **where** it is in the code, **what** was assumed, and **what to try** if it turns out wrong. When you confirm or fix one, delete it from this file, so the file always shows what is still unknown.

The honest headline: **the app runs on Adi's MacBook** (25 September 2026: the notch opens, typing works, `yt` opens YouTube). The first-round guesses below that have not been reported as wrong are still unconfirmed one by one. Section D holds the second round, which compiles but has not been tried.

Earlier headline, kept for history: On 24 September 2026 GitHub's macOS runner (Xcode 16.4, Swift 6.1.2) ran `swift test` (41 tests, all pass) and built the app with no warnings in its own code. Everything below is about what happens when it *runs*.

---

## A. Compile time: resolved

The whole section that used to be here is gone: the first cloud build compiled everything. Two facts from that build worth keeping:

- Resources land at the top of the app bundle (`Consigliere.app/Contents/Resources/open.wav`, `lines.json`), which is where `SoundPlayer` and `Brain` look first.
- The build had one warning, from Apple's tooling about AppIntents metadata. It is harmless and not from this code.

## B. Things likely to misbehave at run time

### The notch window

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B1 | `NotchController.open` | DynamicNotchKit's panel is a non-activating panel that `canBecomeKey`, so calling `makeKey()` lets you type without Consigliere stealing focus from the app you were in. | If typing does nothing: call `NSApp.activate(ignoringOtherApps: true)` just before `window.makeKey()`. If the text field still is not focused, check `focusToken` reaches `InputScreen` and try `DispatchQueue.main.asyncAfter(0.05)` before setting `focused = true`. **This is the single most important thing to get right.** |
| B2 | same | The window exists within a few milliseconds of `expand()` being called, so the loop that waits for it takes the keyboard almost at once. The first one or two keystrokes may still reach the previous app. | Measure. If keys are lost, make the panel key earlier by creating it ahead of time, which needs a small change in the vendored library. |
| B3 | `NotchSensor.swift` | A borderless panel placed over the physical notch, at window level *main menu + 3*, receives clicks and drags there. A fill of 1% opacity is enough for macOS not to pass clicks through. | If clicks do nothing: raise the level (try `.statusBar`, then `.popUpMenu`), and check the frame with a visible colour. If drags are not accepted, confirm `registerForDraggedTypes` ran and try `.screenSaver` level. |
| B4 | `NotchSensor.place` | The sensor is only created on a screen that has a notch. On an external monitor there is none: no click-to-pull and no drop target there. | By design. On those screens, type `bored` to pull, and use the save hotkey to save. |
| B5 | `App/Vendor/…/NotchContentView.swift` | Three coloured `.shadow` layers on the masked notch shape draw the Aurora glow, and fade with the open and close animation. | If the glow is clipped or missing, check the panel is large enough (it is half the screen) and try a smaller radius. If it looks heavy, lower the opacities in the patch or `glowStrength`. |
| B6 | `Views/NotchRootView.swift` | The expanded notch sizes itself to its content (`fixedSize`), so switching screens resizes it with the spring. | If switching screens jumps or clips, give each screen a fixed height, or wrap the switch in `.transition(.opacity)`. |
| B7 | `NotchController.close` | While a timer runs, closing goes to the *compact* state, which shows a dot on the left of the notch and the time on the right. | If compact mode looks wrong or flickers, set `skipIntermediateHides` to `false`, or show the timer only when the notch is opened. |

### Opening things

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B8 | `Opener.openInBrave` | Starting Brave's program file with `--profile-directory=… <address>` while Brave is already running hands the address to the running Brave in that profile, and the new process exits. This is standard Chromium behaviour. | If it opens a second Brave, or the wrong profile: confirm the folder names (DAY_ONE step 6). As a fallback use `open -na "Brave Browser" --args --profile-directory=… <address>`. |
| B9 | `defaults/catalog.json` | Bundle identifiers: `net.whatsapp.WhatsApp`, `com.spotify.client`, `com.valvesoftware.steam`, `com.microsoft.VSCode`. | For any app that will not open: `osascript -e 'id of app "WhatsApp"'` prints the real one. Fix it in settings. |
| B10 | whole app | The target is under 1.5 seconds from Enter to the page being open. Never measured. | Time it. The brain takes well under a millisecond; any delay is in launching Brave. |

### The front tab, Notes, Reminders

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B11 | `TabGrabber.swift` | Brave answers the same AppleScript as Chrome (`URL of active tab of front window`, `title of …`), under the name "Brave Browser". macOS asks once for permission to control it. | If it returns nothing, run the script by hand in Script Editor to see the real error. Check System Settings → Privacy & Security → Automation. |
| B12 | `CaptureWriter.makeNote` | `make new note with properties {body:"…"}` works with HTML in the body, in the default account. `show fresh` brings a new empty note forward. | Test in Script Editor. Some setups need `tell account "iCloud"`. |
| B13 | `CaptureWriter.makeReminder` | `requestFullAccessToReminders` on macOS 14 and later, the older call before that. `defaultCalendarForNewReminders()` is not nil. An `EKAlarm` with an absolute date is what makes the iPhone notify. | If saving fails with no calendar, the Mac has no Reminders account yet: open Reminders once. |

### Voice, sound, ears

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B14 | `Mouth.pickVoice` | At least one Italian voice ("Alice") is installed on a fresh Mac, and `quality.rawValue` orders voices from worst to best. | If he speaks with the default English voice, download an Italian voice (DAY_ONE step 7). |
| B15 | `Mouth.say` | The config's speed (1.0 = normal) maps onto AVSpeech's scale by multiplying the default rate. | If he is too fast or slow, change `theme.voice.rate`; if the mapping is badly off, adjust the formula. |
| B16 | `Ears.swift` | `en-IN` is a supported speech language, ideally on-device. If it is not on-device, macOS sends audio to Apple for recognition. | The settings could show `ears.isOnDevice`; it does not yet. Try `en-US` or `en-GB` in settings if recognition is poor. |
| B17 | `Ears.swift`, `MicTuner.swift` | Each owns its own `AVAudioEngine`. They are never meant to run at once (opening the box stops the tuner). | If the microphone fails to start after using the other one, share a single engine. |
| B18 | `MicTuner.swift` | The tap delivers buffers near the requested 2048 frames, and detecting a 4096-sample window takes a few milliseconds in a release build. In a **debug** build it may be several times slower. | If the needle lags in debug, that is expected; test the tuner in a release build before worrying. |
| B19 | `SoundPlayer.play` | Trackpad taps only happen on a Force Touch trackpad with a finger on it. | Nothing to fix. |

### Ask

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B20 | `AskClient.ask`, `Ask.requestBody` | POST `https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`; body has `model`, `max_tokens`, `system` (a plain string) and `messages`. Checked against Anthropic's documentation in September 2026. The reply has `content[].text` and `usage.input_tokens` / `output_tokens`. | The error text from the API is shown in the notch. If `system` must be a list of blocks, change `Ask.Body`. |
| B21 | `Config.swift`, `AskConfig` | The model name `claude-haiku-4-5` and its price ($1 and $5 per million tokens) are right. Prices are only used to count against the monthly budget. | Change `ask.model` and the two price fields in the config. |
| B22 | `AskClient.Keychain` | A generic-password Keychain item works for an unsandboxed, locally signed app. With ad-hoc signing macOS may ask for the login password on each rebuild. | Sign with your Personal Team (DAY_ONE step 4). |

### Files

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B23 | `Stores.swift`, `stashFile` | iCloud Drive is at `~/Library/Mobile Documents/com~apple~CloudDocs`. | If the stash is not syncing, check that folder exists; otherwise the stash quietly lives in `~/.consigliere`. |
| B24 | `Stores.swift`, `phoneFolder` | The Shortcuts app's iCloud folder is `~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents`. | After building the iPhone shortcuts, find `phone-inbox.txt` in Finder, get its real path, and correct the constant. |

### Hotkeys

| # | Where | Assumed | If wrong |
|---|---|---|---|
| B25 | `Config.swift`, `Hotkeys` | ⌥Space, ⌃⌥Space, ⌃⌥S and ⌃⌥M are free. ⌥Space can clash with input-source switching or another launcher. | Change them in settings. A hotkey needs a normal key at the end; a modifier alone cannot be registered. |
| B26 | `Brain.startTalking` | Holding the talk hotkey sends one key-down and, on release, one key-up (HotKey library, Carbon events). Key repeat does not re-trigger key-down. | If it re-triggers, `startTalking` already ignores calls while listening. |

## C. Known gaps (not guesses: simply not built)

- Ask answers arrive all at once, not word by word as in the phone prototype.
- The settings window cannot edit custom tunings or lines; those are edited in `config.json` and `lines.json`.
- Changing a hotkey takes effect on **Save**, without a restart, but has not been tested.
- The iPhone shortcuts (`docs/IPHONE.md`) have never been built on a phone.
- There is no app icon.

## D. Round two (25 September 2026): compiles, not yet tried on the Mac

| # | Where | Assumed | If wrong |
|---|---|---|---|
| D1 | `App/Consigliere/ScreenRotator.swift`, `App/RotationBridge/.../RotationBridge.m` | **History.** 26 Sep: `180` matched nothing because `config.json` never gained built-ins added after first launch; fixed by `CatalogMigration`, and flip then worked with only the built-in screen. 9 Oct: Adi found it fails *every time an HDMI screen is connected*. Cause not observed directly (no log from that state), so the fix covers every likely one at once: (1) the old code trusted the private call's "fine" and never checked; now each attempt is verified against `CGDisplayRotation`, which macOS keeps honest, and the next way is tried if the screen did not move: a fresh `MPDisplay`, then the `MPDisplay` from MonitorPanel's own `MPDisplayMgr` (how System Settings gets it, the likeliest to respect a multi-screen setup), then legacy IOKit; (2) mirroring: the pair's settings belong to the primary, so the primary is tried too, and undone if it turns only the HDMI screen; (3) lid closed: a built-in screen that is neither active nor mirrored is skipped; (4) the box stays on the laptop screen when flipped, instead of jumping to the HDMI screen. Each attempt writes `~/.consigliere/flip.log`. **Assumed, unverified:** that `MPDisplayMgr` answers `displayWithID:` or `displays`, and that a plain `alloc/init` of it is safe (every call is guarded, so if not, that way just reports "does not know this screen"). | If `180` still fails with HDMI in, the notch line says which case it hit; `cat ~/.consigliere/flip.log` shows every attempt and what macOS reported. That file is all Claude needs to fix the next step. |
| D2 | same | After rotating, macOS does not ask for confirmation (System Settings does, but that is its own separate dialog, not part of this API). | If a "Keep this rotation?" dialog appears and reverts after a few seconds, click Keep, and tell Claude. |
| D3 | `NotchController.close`, DynamicNotchKit | While the screen is upside down, `NSScreen.auxiliaryTopLeftArea` is nil, so the notch is treated as absent: the box appears as a floating pill and the timer has no compact form. | If the notch *is* still reported, the box will draw at the top as usual, which is fine. |
| D4 | `Views/NotchRootView.swift` | The time shown beside the closed notch receives clicks (DynamicNotchKit's window does not ignore mouse events, and the text has a hit area). | If clicking the time does nothing, type `timer` to open the timer screen, and look at the compact views' `contentShape`. |
| D5 | `CaptureWriter.makeNote` | `make new note` returns the note, and `id of` it is a string like `x-coredata://…` that `show note id "…"` accepts later. | If clicking a note in the glance only opens Notes, the id is empty or not accepted; the fallback already opens Notes. |
| D6 | `CaptureWriter.upcomingReminders` | `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` returns undone reminders from every list, with or without a date. | If the glance is empty but Reminders is not, try passing `store.calendars(for: .reminder)` as the calendars. |
| D7 | `AppIndex.swift` | Scanning /Applications (and one level down), Utilities, /System/Applications and ~/Applications finds the apps, and `FileManager.displayName` gives their proper names. Apps from the Mac App Store and Steam's own app are in /Applications. | If an app is missing, add it in settings with **Add an app**. Steam *games* live elsewhere and are not scanned. |
| D8 | `Brain.searchable` | Matching against a few hundred installed apps as well as the catalog stays instant (the matcher is a few microseconds per name). | If typing feels slower, measure `Matcher.match`; the installed list can be matched only when the catalog has no strong result. |
| D9 | `TutorialWindow.swift` | A borderless-looking titled window with a black background shows once, 1.5 s after the first launch, without fighting the permission prompts. | If it appears behind the prompts, raise the delay. It remembers it was seen in the user defaults key `brochacho.tutorialSeen.v1`. |
| D10 | `scripts/install.sh` | `security find-identity -v -p codesigning` lists an "Apple Development" certificate once an Apple ID is added in Xcode, and signing with it keeps macOS permissions across updates. On the cloud Mac it builds and signs ad hoc correctly. | If permissions are asked again after every update, check the script printed "Signed as: Apple Development…". |
| D11 | `Theme.swift`, vendored `NotchView.swift` | The Nocturne look: `HelveticaNeue-Thin` exists on macOS; the bundled mono font registers at launch; the grain tiles at 6% without costing noticeable battery; the rim line sits exactly on the notch's bottom edge. | If a label shows in the system font, the font did not register (check the log for "font … is missing"). If the rim floats above the edge, move it in the vendored `NotchView.swift`. If the grain is too visible or not visible, change `theme.look.grain`. |

## E. Round three (11 October 2026): version 2, compiles, not yet tried on the Mac

Confirmed on 11 October and removed from the table: music by name. `play arctic monkeys` searches Spotify and plays the artist's top song in the artist's context. What it took: AppleScript on the main thread, a song address rather than an artist address, and a correctly pasted client secret (a wrong one now says so in the notch; each attempt is in `~/.consigliere/music.log`).

| # | Where | Assumed | If wrong |
|---|---|---|---|
| E1 | `Character/Roamer.swift` | A borderless non-activating panel at *main menu + 1*, moved with `setFrame` 30 times a second, stays above ordinary windows (and full-screen apps, via `.fullScreenAuxiliary`) and below the notch. Clicks on him reach `ClickCatcher` without Consigliere stealing focus. | If he is hidden behind windows, raise the level to `.statusBar`. If clicks do nothing, try `.popUpMenu` level, and check `acceptsFirstMouse`. If the motion stutters or the fan spins, lower the rate to 20 a second. |
| E2 | `Character/JobCard.swift` | SwiftUI buttons in a non-key panel answer the first click because the hosting view `acceptsFirstMouse`. | If the first click only "wakes" the card, call `panel.makeKey()` after showing it. |
| E3 | `FocusFilter.swift` | macOS finds the `SetFocusFilterIntent` in an unsandboxed, locally signed app installed in /Applications, lists it under Focus filters, and calls `perform()` in the running app when the Focus turns on (with the switch) and off (with the default, false). | If Consigliere is not in the Focus filters list, rebuild with the app in /Applications and log out and in. Fallback: type `quiet`, or switch off **He may fly out** in settings. If he stays in after the Focus ends, the "off" call did not arrive; `defaults delete com.adi.brochacho brochacho.focusQuiet` resets it. |
| E4 | `Brain.checkJobs` | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: ~0)` gives seconds since any key press or mouse move, with no permission prompt. | If he never comes out, log `idle`; if it is always huge, try `.hidSystemState`. |
| E6 | `defaults/catalog.json` | Books' bundle identifier is `com.apple.iBooksX`. | `osascript -e 'id of app "Books"'` prints the real one; the opener also finds it by name. |
| E7 | `CaptureWriter.appendToDiary` | `set body of theNote to (body of theNote) & "<div>…</div>"` appends without disturbing the note, and a note whose id no longer exists makes `note id` fail inside `try`, so a fresh note is made. | Test in Script Editor. If the note's title is not "Consigliere diary · …", the first `<h1>` did not become the title; make it a plain first line. |
| E8 | `Character/CharacterSprite.swift` | `Image(nsImage:).interpolation(.none)` keeps pixel art sharp at 64 points and larger. | If he looks blurry, scale the PNGs up yourself (whole multiples) before dropping them in. |
| E9 | `NotchController.close`, vendored DynamicNotchKit | The compact form beside the closed notch can show his head (when a job waits and he is held in) as well as the timer. | If the head never shows, the compact form is only used while a timer runs; open the list with `jobs` instead. |
| E10 | `Brain.showJobs(byItself:)` | The once-a-day list opens without taking the keyboard, and a click on its add line makes the notch window key so typing goes there. | If clicking the line does not let you type, type `jobs` instead (that takes the keyboard). The fix is to make the window key on click in the vendored panel. |
| E11 | `Views/JobsScreen.swift` | The pixel explosion (bits up to 40 points out from the box) is drawn even beyond the row; the notch's shape may clip the part outside the list. A right-click menu (`contextMenu`) works inside the notch window. | If the explosion is cut off, shorten the distances in `PixelBoom.bits`. If right-click does nothing, tick-and-untick still works; delete needs another way in. |
| E12 | `Character/CharacterSprite.swift` | `NSBitmapImageRep` gives every frame of an animated GIF through `.currentFrame`, with `.currentFrameDuration`. | If the GIF shows one still frame, split it into PNGs (`idle_0.png`…) instead. |
| E13 | `Character/Roamer.swift` (`ClickCatcher`) | The window around him is transparent outside his body, so clicks there fall through to the app underneath; mouse-moved events arrive over his body without the window being key (`acceptsMouseMovedEvents`, an `.activeAlways` tracking area), which is what petting needs; `mouseDragged` keeps arriving while he is dragged even though the window moves under the cursor. | If clicks near him are swallowed, shrink the margin in `layout()`. If petting never makes hearts, log in `mouseMoved`. If dragging stutters or drops him, move the window from the drag delta instead of the absolute mouse position. |

