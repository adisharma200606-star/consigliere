# Read this first

You are picking up **Consigliere**, a Mac app that lives in the MacBook notch: type or say the name of a thing and it opens, drag something onto the notch and it is saved, click the notch and one saved thing comes back, and an Italian-accented voice says a short line after each action. Since version 2 he also keeps the day's **jobs** (a to-do list where every job knows what to open), lives in the notch as a small **character** who flies out silently when a job is due, keeps a **diary** in Apple Notes, and plays music by name. It was designed and written for one person, Adi, who is a self-taught builder with no computer-science background. Explain things to him in plain language, teach as you go, and be honest rather than flattering. He asked for that explicitly.

## Updating the app on Adi's Mac

After pushing a change, wait for the CI run to finish (it commits the regenerated Xcode project back to `main`), then Adi runs `~/Code/consigliere/scripts/install.sh`, which pulls, builds a Release copy, signs it, installs it in /Applications and relaunches it.

## The single most important fact

**Consigliere runs on Adi's MacBook and he uses it every day** (version 1 since 25 September 2026, version 2 since 11 October). Confirmed by use: opening things, the notch and its look, settings, the timer, flip (with and without an HDMI screen), music on Spotify, jobs, and the character. Not yet confirmed one by one: hold-to-talk, the tuner's microphone, Ask, Notes/Reminders/diary, living bookmarks, the Focus filter, Apple Music. `BLIND_SPOTS.md` sections B and E list the runtime guesses behind those.

Also tested: the JavaScript reference implementation of the brain (`reference-js/`, 51 passing tests) and the phone prototype built on it.

## What to do, in order

1. Read `DAY_ONE.md` and follow it with Adi. It goes from a fresh Mac to a running app.
2. `swift test` at the repo root. It passes on the cloud Mac; if it fails here, see "How the tests work" below before touching any test or fixture.
3. `cd App && xcodegen generate`, then build the `Consigliere` scheme. It builds on the cloud Mac.
4. Run it. Walk through the smoke test at the end of `DAY_ONE.md`. For each thing that misbehaves, look in `BLIND_SPOTS.md` first: the likely cause is probably already written down.
5. When something in `docs/GUIDE.md` turns out to be wrong, fix the guide too, and update its Status lines. The guide is Adi's manual and it must stay true.

## Rules of the product. Do not break these while fixing things.

1. **The action happens first.** The line, the sound and the voice come after and never delay it.
2. **Fast.** Under 1.5 seconds from Enter to the thing being open. Measure it; treat a regression as a bug.
3. **Nothing to memorise.** The box matches *names*. There is no command language. Anything that is not "open a thing" is a gesture, a hotkey, or a tool that is itself just a name (`timer 10`, `note buy strings`).
4. **He never *speaks* first.** Voice and sound only answer something the person just did, or something they asked to be told (a timer ending). The character **never leaves the notch on his own** (Adi, 13 October 2026: "do not let him linger around ever"). Jobs never bring him out: the code path is gone and `character.roam` is ignored (29 October 2026). A due job shows his head beside the notch, and that head is the reminder Adi wants (24 October 2026: "i just wanted him in the notch, staring at me to indicate a task is due"; 29 October: "i don't want him flying out of the notch"). Do not make him fly out for jobs again, and do not make the head depend on any setting. `pet` brings him out for at most 45 seconds, and home after 12 seconds untouched. The one other thing that shows unasked: once a day from `jobs.openListAt` (10:00) the jobs checklist opens by itself, silently, without taking the keyboard.
5. **One character, nothing more.** Adi reversed the old "no character" rule on 11 October 2026: a small sprite lives in the notch (his own art goes in `~/.consigliere/character/`, never in the repo). `pet` brings him out to be played with (petted, thrown, follow, fetch); he only talks right after something done to him, and goes home silently when left alone. Still no streaks, no dashboards, no watching the screen. He knows only the clock, the jobs Adi typed, and whether the Mac is being used (idle seconds, never content). Jobs carried over are "owed", not a streak.
6. **Version 2 is the current scope** (jobs, character, diary, music: `docs/GUIDE.md` sections 20 to 23). New ideas go in the parked list at the end of `docs/GUIDE.md` until Adi asks for them. The tone for jobs is Sopranos: jobs, favours, what's owed.

## Map of the repo

| Path | What it is |
|---|---|
| `docs/GUIDE.md` | Adi's manual: every feature, every setting. Each section has an honest Status line. |
| `docs/ARCHITECTURE.md` | How the code fits together, file by file. Read this before changing the app. |
| `DAY_ONE.md` | Fresh Mac to running app, step by step. |
| `BLIND_SPOTS.md` | Every assumption that could not be checked without a Mac, and what to try if it is wrong. |
| `REFERENCES.md` | Third-party code and licences. |
| `reference-js/` | **The source of truth for behaviour.** Matcher, stash, lines, tuner, timer, bookmarks, reminders, asking, jobs. Plain JavaScript with tests. |
| `fixtures/` | Golden test data written by the JS tests. The Swift tests load these and must reproduce them. |
| `Sources/ConsigliereCore/`, `Tests/` | The brain ported to Swift. Foundation only, no UI. Must behave exactly like `reference-js/`. |
| `App/` | The Mac app. `project.yml` generates the Xcode project. `Consigliere/` is the source. `Vendor/DynamicNotchKit` is a lightly patched copy of the notch-window library. |
| `defaults/` | Shared data: the catalog of things to open, the tunings, the 367 lines. |
| `scripts/` | Generators: Swift defaults from the shared JSON, the lines, the sounds, the dragon. |
| `prototype/` | The phone prototype (a single web page). Useful as a picture of how every screen should look and feel. |
| `docs/IPHONE.md` | Two iPhone Shortcuts that save to and pull from the same stash. Untested; not the priority. |
| `App/Consigliere/Character/` | The character: his frames, the window he roams in, and the job card beside him. |

## How the tests work. Read before "fixing" a failing test.

Behaviour is defined once, in JavaScript, and checked twice:

```
reference-js/*.js  --(node --test)-->  hand-written expectations pass  -->  writes fixtures/*.json
Sources/ConsigliereCore/*.swift  --(swift test)-->  must reproduce fixtures/*.json exactly
```

- If a Swift test fails, the Swift port is wrong (or will not compile). Fix the Swift. **Never edit a fixture by hand.**
- If the *behaviour* should change, change `reference-js/`, update its hand-written expectations, run `node --test reference-js/*.test.js` (this rewrites the fixtures), then bring the Swift into line.
- `Sources/ConsigliereCore/DefaultCatalog.swift` and `DefaultTunings.swift` are generated. Edit `defaults/*.json` and run `python3 scripts/gen_default_catalog.py` / `gen_default_tunings.py`.
- After editing `defaults/lines.json` (or `scripts/build_lines.py`), run `python3 scripts/sync_app_resources.py` so the app bundles the new lines.
- The bundled dragon is drawn by `scripts/make_sprites.py`. Rerun it after changing him.
- Node versions differ in the last digit of some floats, so running the JS tests locally can rewrite `fixtures/tuner.json` with no real change. If that is the only fixture diff, `git checkout fixtures/tuner.json` rather than committing it.

## Conventions

- Comments explain *why*, in plain words, because the owner of this code is learning. Keep that up.
- The app target is deliberately thin. Logic belongs in `ConsigliereCore`, where it can be tested without a Mac's UI.
- `Brain.swift` is the only class that knows about all the others. Views never do work; they read `NotchModel` and call the closures on it.
- Secrets: the Claude API key and the Spotify keys live in the Keychain (`AskClient.Keychain`). Never write them to a file or a log.
