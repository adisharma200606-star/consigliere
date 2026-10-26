# How Consigliere fits together

Written so that someone (or a Claude session) who has never seen the code can find their way around in ten minutes.

## The shape of it

```
   you                                   the Mac app (App/Consigliere)                          the brain (ConsigliereCore)
 ────────                          ───────────────────────────────────────                  ──────────────────────────────
  hotkey  ───────▶ HotkeyCenter ─┐
  click / drop ──▶ NotchSensor ──┤
  typing ────────▶ InputScreen ──┼──▶  Brain  ──── "what did he mean?" ───────────────────▶  Matcher  ──▶ Decision
  voice ─────────▶ Ears ─────────┘      │   ◀─── "then do this" ──────────────────────────  ActionPlan
                                        │
                                        ├──▶ Opener          opens it (Brave with the right profile, apps, folders)   ← always first
                                        ├──▶ NotchModel ──▶ the screens inside the notch (Views/)
                                        ├──▶ NotchController ──▶ DynamicNotchKit (opens, closes, glow, spring)
                                        ├──▶ SoundPlayer     sounds and trackpad taps     ◀── Feedback.spec
                                        ├──▶ Mouth           the Italian voice            ◀── Lines.pick
                                        ├──▶ MicTuner ─────▶ PitchDetector ─▶ TunerSession ─▶ TunerDisplay
                                        ├──▶ CaptureWriter   Apple Notes, Apple Reminders ◀── ReminderParser
                                        ├──▶ AskClient       Claude API, Keychain, budget ◀── Ask.build / Ask.shape
                                        └──▶ stores          config, usage, stash, line history, phone files
```

Two ideas explain most of the design:

1. **The brain decides, the app does.** `ConsigliereCore` has no UI, no network, no clock and no randomness of its own; time and random numbers are handed in. That is what lets it be tested completely without a Mac, and checked against the JavaScript reference line by line.
2. **One class knows everything; nothing else does.** `Brain` is the only place that touches all the parts. Views hold no logic, and the helper classes do one job each and know nothing about one another.

## The brain: `Sources/ConsigliereCore`

| File | What it answers |
|---|---|
| `TextTools.swift` | Small text helpers: normalising, edit distance, percent-encoding. |
| `Catalog.swift` | What one "thing he can open" looks like (`CatalogEntry`). |
| `Matcher.swift` | "He typed `yt berserk`. What did he mean?" Returns a `Decision`: open, search, ask, empty or nothing. |
| `ActionPlan.swift` | Turns a `Decision` into a plain instruction: open this URL in this profile, open this app, show this tool, ask this question. |
| `Stash.swift` | Saved things, and the rules for handing one back (never repeat, mix fresh and old, skipped things go to the back). |
| `Lines.swift` | Which line he says, never repeating the last five, and whether it is spoken this time. |
| `Tuner.swift` | Note maths, YIN pitch detection, string matching, and `TunerSession`, which steadies the display. |
| `Extras.swift` | The timer (reading "1h30", counting down, adding time, words that mean stop), living bookmarks (which entry moves), and folding the iPhone's files into the stash. |
| `CaptureLog.swift` | The short list of notes and reminders made from the notch, for the glance; and `InstalledApps`, which turns the apps found on disk into things the box can open. |
| `CatalogMigration.swift` | Keeps an existing `config.json` in step with new built-in commands added in later updates — see the note below. |
| `Capture.swift` | Reading "call mom tomorrow at 5" into a title and a time. |
| `Jobs.swift` | The day's jobs: reading "read 30 min, duolingo by 10pm", which of his things starts each job, carrying unfinished jobs to the next day, and `Jobs.nextNudge`, which decides when the character comes out, about what, and how boldly. Port of `reference-js/jobs.js`. |
| `Ask.swift` | What is sent with a question, when the clipboard is included, and splitting the reply into text and a command. |
| `Feedback.swift` | Which sound and which trackpad tap go with each event. |
| `Config.swift` | Every setting, each with a default, so a partial or old config file always loads. |
| `Stores.swift` | Where files live, and reading and writing them safely (atomic writes; a broken file is never deleted). |
| `DefaultCatalog.swift`, `DefaultTunings.swift` | **Generated** from `defaults/*.json`. Do not edit by hand. |

Each of these is a port of a file in `reference-js/`. The port is kept honest by `fixtures/*.json`: the JavaScript tests write them, and the Swift tests must reproduce them.

## The app: `App/Consigliere`

| File | Job |
|---|---|
| `ConsigliereApp.swift` | Entry point. No main window. `AppDelegate` creates the `Brain`. |
| `Brain.swift` | **Start here.** Every feature is a short method: `openBox`, `submit`, `run`, `showLine`, `pull`, `saveFrontTab`, `markMyPlace`, `startTalking`, `openTuner`, `startTimer`, `capture`, `ask`. |
| `NotchModel.swift` | Everything the notch shows, as published properties, plus the closures the views call. |
| `NotchController.swift` | Wraps DynamicNotchKit. Adds what a launcher needs: the keyboard from the first moment, Escape, arrow keys, click-away. |
| `NotchSensor.swift` | An invisible window over the physical notch that is always there, because DynamicNotchKit removes its own window when closed. Click = pull, right-click = menu, drop = save. |
| `Views/` | One file per screen: `InputScreen`, `LineScreen` (also `PullScreen`, `ChooserScreen`), `TunerScreen`, `AnswerScreen`, `TimerScreen`, `GlanceScreen`, and `NotchRootView`, which switches between them and holds the small timer shown beside the closed notch. |
| `Theme.swift` | The Nocturne look: config values turned into the accent, ink colours, Helvetica and mono fonts, the spring, the grain texture; registers the bundled fonts at launch. |
| `HotkeyCenter.swift` | "ctrl+opt+space" from the config into a registered hotkey, with key-down and key-up. |
| `Opener.swift` | Carries out an `ActionPlan`. Launches Brave's program file directly so the profile flag survives. |
| `TabGrabber.swift` | Asks the front browser for its page, by AppleScript. |
| `Mouth.swift` | The voice: an Italian system voice reading English, or a recorded clip if one exists for the line. |
| `SoundPlayer.swift` | Plays the eight sounds and the trackpad taps. |
| `Ears.swift` | Hold-to-talk speech recognition. |
| `MicTuner.swift` | Microphone into the pitch detector, about twelve readings a second. |
| `CaptureWriter.swift` | Makes the note (AppleScript, keeping its id) or the reminder (EventKit); reads upcoming reminders and ticks them off; reopens a note by id; appends to the day's diary note. |
| `ScreenRotator.swift` | `one eighty`: picks the screen (laptop when the lid is open, else main), asks `RotationBridge` to rotate it one way at a time, checks with `CGDisplayRotation` that it really turned before trying the next way, handles mirroring, and writes `~/.consigliere/flip.log`. |
| `AppIndex.swift` | Finds installed apps so any of them opens by name. |
| `TutorialWindow.swift` | The three slides. |
| `AskClient.swift` | One HTTPS call to the Claude API. Key in the Keychain (which also holds the Spotify keys). Monthly spending ledger. |
| `Character/CharacterSprite.swift` | The character's frames (from `~/.consigliere/character/`, else the bundled dragon) and the animated view. |
| `Character/Roamer.swift` | The small window he flies around the screen in. The window *is* him, so every other click goes through. Paths per boldness level, flying out from and back into the notch. |
| `Character/JobCard.swift` | The card beside him when he is clicked: the job, a line, two or three buttons. |
| `FocusFilter.swift` | A Focus filter (AppIntents) that keeps him in the notch during the Focus modes Adi picks. |
| `MusicPlayer.swift` | "play beabadoobee": Spotify's search (with a free key) or Apple Music's library, then AppleScript to play. Pause, next, volume. |
| `SettingsWindow.swift` | The settings window: things, voice and sound, Ask, hotkeys and files. |
| `Resources/` | `lines.json` (copied from `defaults/` by `scripts/sync_app_resources.py`), `sounds/*.wav` (made by `scripts/make_sounds.py`), `fonts/` (IBM Plex Mono) and `textures/grain.png`. Xcode flattens all of these into the top of the app's Resources folder. |

## Why an existing config.json needs a migration

`config.json` is written once, the very first time Consigliere runs, with whichever built-in commands
existed in `DefaultCatalog.entries` at that moment. Every command added in a later update — `flip`,
`settings`, `help`, `bored`, and whatever comes after them — would otherwise never reach someone who
already has a config.json, no matter how many times they update: loading a config that already has a
`catalog` array just uses it as-is.

`CatalogMigration.merge`, run once at every launch (`Brain.init`, right after loading the config), fixes
this: it adds any built-in entry that is missing and has never been offered before, and remembers every
built-in it has ever offered in a small separate file, `catalog-migrations.json` — so if the person deletes
a built-in on purpose from Settings, it stays deleted forever rather than reappearing on the next update.
Nothing about a person's own entries is ever touched.

This is also the actual root cause found for "`180` does nothing": on Adi's Mac, `flip` (and `settings`,
`help`, `bored`) had simply never existed in his live catalog, because his config.json predated them.

## Why rotation is Objective-C, not Swift

Everything else in `App/Consigliere` is Swift. `App/RotationBridge` is a small, separate, all-Objective-C
Swift Package (like `App/Vendor/DynamicNotchKit`, but original code, not vendored). The reason: rotating the
screen means calling a private, undocumented macOS class (`MPDisplay`) that has no header anywhere. In
Objective-C, one line — a category that just *declares* the two method names exist — is enough to let the
compiler accept a completely ordinary `[[cls alloc] initWithCGSDisplayID:...]` call, which then runs
correctly at run time against whatever class `cls` actually is. Doing the equivalent from Swift means manually
resolving `alloc`/`init` through the Objective-C runtime with raw C function pointers — which a first attempt
at this got wrong, silently, with no compiler to catch it. See `RotationBridge.m` for the actual code and
`BLIND_SPOTS.md` D1 for the history.

## What happens when he types `yt` and presses Enter

1. The **open** hotkey fires. `HotkeyCenter` calls `Brain.toggleBox`, which calls `openBox`.
2. `openBox` resets `NotchModel` to the input screen and calls `NotchController.open(takeKeyboard: true)`. The controller asks DynamicNotchKit to expand and, without waiting for the animation, makes the new window take the keyboard. `SoundPlayer` plays *open*.
3. Each keystroke reaches `InputScreen`'s text field, which calls `model.onTextChange`, which is `Brain.textChanged`. That runs `Matcher.match` and publishes the rows.
4. Enter calls `Brain.submit`. `ActionPlan.make` turns the decision into `.openURL(youtube, profile: personal)`.
5. `Brain.run` calls **`Opener.run` first**. Brave gets the address.
6. Then `count` bumps the usage counter, and `showLine` picks a line (`Lines.pick`), shows it, maybe says it (`Mouth`), and schedules the notch to close.

Every other feature follows the same pattern: a trigger, a decision from the brain, the action, then the line.

## What happens when a job is due

1. Every 30 seconds `Brain.checkJobs` asks `Jobs.nextNudge` (pure, tested) whether he should come out. It knows only the clock, `jobs.json`, the settings, whether a Focus filter or `quiet` is holding him in, and how many seconds since the last key press or mouse move.
2. If so, `Roamer.flyOut` sends him out of the notch at the right boldness. No sound, no voice.
3. A click opens `JobCard`. **start it** runs the job's starter through `Opener` first (rule 1), starts the timer for the job's length, then says a line. He flies home.
4. If nobody clicks him, `Roamer` gives up after `jobs.roamMinutes`, and `JobDay.ignored` makes the next visit one level bolder.

## Threads

Everything in the app runs on the main thread (`@MainActor`) except two things that would make it stutter: pitch detection (`MicTuner` uses its own queue and hops back to the main thread with each reading) and the network call in `AskClient` (async/await). Speech recognition calls back on its own thread and hops to the main thread at once.

## Files it reads and writes

See "Where your files live" in `docs/GUIDE.md`. The only secret, the API key, is in the Keychain.
