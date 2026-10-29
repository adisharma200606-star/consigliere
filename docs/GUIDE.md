# Consigliere — the guide

Everything Consigliere does, how to use it, and how to change it. Written for you, not for programmers.

**Read this first:** this guide describes how each feature *will* behave, and it is also the checklist the app is being built against. Each section starts with a **Status** line so you always know what is real today:

- **Brain tested** — the logic exists, runs, and passes tests (in JavaScript, in `reference-js/`).
- **Swift written** — the same logic is ported to Swift for the Mac. It passes a syntax check. It has not been compiled yet.
- **Mac app builds** — the part you see and touch on the Mac exists and compiles cleanly on GitHub's cloud Mac. It has never been *run*, so treat it as a first draft until day one is done.

When the app runs on your Mac, every Status line gets updated and anything that turned out different gets rewritten. If the guide and the app ever disagree, that is a bug in one of them. Tell me.

---

## Contents

1. [What it is](#1-what-it-is)
2. [Opening things](#2-opening-things)
3. [Talking instead of typing](#3-talking-instead-of-typing)
4. [Saving things (the stash)](#4-saving-things-the-stash)
5. [Getting things back](#5-getting-things-back)
6. [Bookmarks that remember where you stopped](#6-bookmarks-that-remember-where-you-stopped)
7. [The tuner](#7-the-tuner)
8. [The timer](#8-the-timer)
9. [Notes and reminders](#9-notes-and-reminders)
9½. [Flipping the screen](#9-flipping-the-screen)
10. [Ask](#10-ask)
11. [The voice](#11-the-voice)
12. [Sounds and touch](#12-sounds-and-touch)
13. [Adding your own things](#13-adding-your-own-things)
14. [Look and feel](#14-look-and-feel)
15. [Hotkeys](#15-hotkeys)
16. [The config file, key by key](#16-the-config-file-key-by-key)
17. [Where your files live](#17-where-your-files-live)
18. [When something goes wrong](#18-when-something-goes-wrong)
19. [What is built and what is not](#19-what-is-built-and-what-is-not)
20. [Jobs](#20-jobs)
21. [The character](#21-the-character)
22. [The diary](#22-the-diary)
23. [Music](#23-music)

---

## 1. What it is

Consigliere lives in the notch at the top of your MacBook screen. Most of the time you cannot see it. You call it, it does one thing fast, an Italian voice says a short line, and it disappears.

It follows five rules. They explain most of the choices below.

1. **The action comes first, the voice after.** He never makes you wait for a joke.
2. **Fast.** Under a second and a half from Enter to the thing being open.
3. **Nothing to memorise.** You type the *name* of what you want. There are no commands.
4. **He never speaks first.** He only talks in reply to something you just did, or something you asked him to tell you (like a timer ending). He never leaves the notch on his own: only `pet` brings him out, and not for long (section 21).
5. **One little character, and nothing that watches you.** No streaks, no dashboards, no watching your screen. (The character arrived in version 2; before that the rule was "no face" too.)

---

## 2. Opening things

**Status:** brain tested · in daily use on Adi's Mac since 25 Sep 2026

Press the **open** hotkey. The notch grows into a box. Type the name of the thing. Press Enter. It opens, the notch closes, he says a line.

### You can be lazy

| You type | What happens | Why |
|---|---|---|
| `yt` | YouTube | `yt` is a nickname (an *alias*) for YouTube |
| `you` | YouTube | the start of a name is enough |
| `y` | YouTube | even one letter, if nothing you use more starts with it |
| `code` | VS Code | a later word of the name works too |
| `ytb`, `linkdin` | YouTube, LinkedIn | skipped or missing letters are forgiven |
| `steem`, `cloud` | Steam, Claude | small typos are forgiven |

Up to four matches show under what you type. The top one is what Enter opens. Tap or click another row to open that one instead.

**When two things match equally well, the one you open more often wins.** Type `s` and you get Steam or Spotify depending on which you actually use. It learns this by counting, nothing cleverer.

Open the box and type nothing, and you see the four things you open most.

### Searching inside a site

Type a site's name, then what you want:

- `yt berserk amv` opens YouTube's search results for "berserk amv"
- `g how to tune a guitar` searches Google
- `gh dynamicnotchkit` searches GitHub

This works for any site that has a *search address* set (see [Adding your own things](#11-adding-your-own-things)).

### Extra words are ignored

`open youtube`, `play me some youtube`, `go to gmail`, `open the downloads folder` all work. Words like *open, play, me, some, the, go, to, please, set* carry no meaning, so they are dropped. This matters most when you talk.

### Sites open in the right Brave profile

Every site entry says which Brave profile it belongs to, `personal` or `work`. Consigliere launches Brave with that profile directly, so your personal YouTube never opens in your work window.

### If he does not know it

If it is a single word he does not know, he shows `?`, says something like "Never heard of it", and nothing opens. Add it (section 13). If it is several words, he treats it as a question (section 10).

---

## 3. Talking instead of typing

**Status:** brain tested (spoken words go through the same matcher) · Mac app builds, never run · needs the Mac's microphone

**Hold** the talk key, say the name, **let go**. Letting go is what tells it you have finished, which is why it is faster than a button you tap.

- Speech is recognised on the Mac itself. Nothing is sent anywhere.
- You do not say "Consigliere". Just say the thing: "YouTube", "open Steam", "timer ten minutes".
- Mishearings are handled: "you to", "get hub", "what's app", "linked in" all land correctly.
- **If he is not sure, he does not guess.** He shows his best guess with a `?` and waits for Enter. Opening the wrong thing is worse than opening nothing.

Expect to type more than you talk. Typing `yt` is faster than speaking, and it works in class.

---

## 4. Saving things (the stash)

**Status:** brain tested · Swift written · Mac app builds, never run

You find something good and want it later. Three ways to save it, none of which ask you a single question:

1. **Drag it onto the notch.** A link, some text, an image, a file. The notch swallows it.
2. **Press the save hotkey** while looking at a page in Brave. It saves that tab. No window appears.
3. **From your iPhone:** a share-sheet shortcut. See `docs/IPHONE.md` for the build steps. There is a matching **Bored** shortcut for getting things back on the phone, and both work for someone who only has an iPhone.

There are no folders and no tags. The moment a saving tool asks where something goes, people stop using it.

Saving the same thing twice does not make a duplicate. It just counts as freshly saved.

---

## 5. Getting things back

**Status:** brain tested · Swift written · Mac app builds, never run

This is the half that other "save for later" tools get wrong. They make you go and look. Consigliere hands things back at the moment you were about to go looking for a distraction anyway.

**Click the notch**, or type `bored`. He opens **one** thing you saved.

- For a few seconds a small **another** button shows. Click it and he puts that one back and opens a different one. No commentary.
- Something you opened is never served again.
- He alternates between things from the last two weeks and older things, so old finds do not rot at the bottom.
- Something you skip three times goes to the back of the queue.
- If the stash is empty he says so. No guilt.

---

## 6. Bookmarks that remember where you stopped

**Status:** brain tested · Swift written · Mac app builds, never run

A normal entry always opens the same page. A **living** entry opens wherever you last were.

**Example.** You make an entry called `bat` while on chapter 3 of Absolute Batman, and tick **remember where I left off**. Later you are on chapter 14. You press the **mark my place** hotkey. From now on `bat` opens chapter 14.

How he decides which entry to move:

- **Only living entries ever move.** `youtube` is not living, so pressing the hotkey on a YouTube video never overwrites it.
- If exactly one living entry belongs to the site you are on, he moves it.
- If several do (two manga on the same reader site), he picks the one whose address looks most like the page you are on (`/manga/absolute-batman/...` matches `bat`, not `berserk`).
- If he still cannot tell (two Netflix shows, whose addresses are just numbers), he shows both in the notch and you pick.
- If nothing living belongs to this site, he offers to make a new entry from the page.

Good uses: manga, a course, a long playlist, documentation you are working through, a show.

Limit: he can open the page. He cannot press play or scroll to your line. For Netflix, save the *watch* page and it resumes by itself.

---

## 7. The tuner

**Status:** brain tested (accurate to about a quarter of a cent on test tones) · Swift written · Mac screen and microphone hookup build, never run

Type `tune`, `tuner` or `uke`. The notch becomes a tuner. Pluck a string.

### Reading it

- The **big letter** is the string it thinks you are tuning. It works this out by itself.
- The **needle** shows how far off you are. Left is flat (tune up), right is sharp (tune down). The number is in *cents*; 100 cents is one fret.
- When the needle sits in the middle and holds for about a third of a second, the display flips to **in tune**. It waits that moment on purpose so a passing wobble does not count.
- Strings you have already got right are underlined.
- When **every** string has been in tune once, he says one line ("Bellissimo. She sings."). Once per session, not once per string.

One stray sound (a knock on the desk, a harmonic) will not make it jump to another string. It only switches when two readings in a row agree.

### Tunings

Arrows flip through them.

| Guitar | Strings (low to high) |
|---|---|
| Standard | E A D G B E |
| Half step down | Eb Ab Db Gb Bb Eb |
| Full step down | D G C F A D |
| Drop D | D A D G B E |
| Double drop D | D A D G B D |
| DADGAD | D A D G A D |
| Open G | D G D G B D |
| Open D | D A D F# A D |
| Open E | E B E G# B E |
| Open C | C G C G C E |
| Drop C | C G C F A D |
| Drop B | B F# B E G# C# |
| Drop A | A E A D F# B |

| Ukulele | Strings (4th to 1st) |
|---|---|
| Standard (high G) | G C E A |
| Low G | G C E A, with the G an octave lower |
| Baritone | D G B E |
| D tuning | A D F# B |

**Chromatic** mode shows the nearest note of any kind, with its octave. Use it for anything not in the list, or for other instruments.

### Your own tunings

Add them under `tuner.customTunings` in the config (section 16). Notes are written as letter, optional `#` or `b`, and octave number: `E2`, `F#3`, `Bb3`. Middle C is `C4`.

### Settings

- `tuner.a4` — the pitch of A. 440 unless you are playing along with something tuned differently.
- `tuner.toleranceCents` — how close counts as in tune. Default 5. A good ear stops hearing the difference around there.

### Honest limits

- **Drop B and Drop A** put the lowest strings around 55 to 62 Hz. Laptop microphones are weak down there. Those strings will read, but slower and jumpier than the rest.
- While the tuner is open, macOS shows its orange microphone dot. That is normal. The microphone turns off when the tuner closes.
- A slack new string far below pitch shows as "way flat" on the nearest string. It never pretends to be in tune.

---

## 8. The timer

**Status:** brain tested · in use on Adi's Mac

Type `timer` and how long. The notch closes, and the time left shows beside it. When it ends, he tells you. (You asked him to, so rule 4 holds.)

| You type | You get |
|---|---|
| `timer 10` | 10 minutes. A bare number means minutes. |
| `timer 1.5` | 90 seconds |
| `timer 90s` · `timer 45 seconds` | seconds |
| `timer 25 min` · `timer 10m` | minutes |
| `timer 1h` · `timer 1h30` · `timer 1 hour 30 minutes` | hours |
| `timer 5m30` | 5 minutes 30 seconds |
| `timer 1:30` · `timer 1:30:00` | clock style |
| `10 min timer` · `set a timer for 10 minutes` | the natural way round works too |
| `countdown 5` | `countdown` is a nickname for the timer |

**Controlling it while it runs**

- **Click the time** beside the notch, or type `timer` on its own. The timer screen opens: the time left in big numbers, a bar draining in the glow colours, and three buttons: **Stop**, **+1 min**, **+5 min**.
- `timer stop`, `stop timer`, `cancel the timer`: stops it straight away.
- Right-click the notch → **Cancel the timer** also works.
- Adding time to a timer that has just finished starts it again from now.

Shortest is one second, longest is 24 hours. There is one timer at a time. If he cannot read what you typed ("timer soon"), he says so and starts nothing.

While the screen is flipped (`one eighty`), there is no notch to sit beside, so the time is only visible on the timer screen.

---

## 9. Notes and reminders

**Status:** brain tested (reading the time out of what you typed) · working in the phone prototype · Mac app builds, never run

A thought arrives while you are in the middle of something. Type it into the notch and carry on. You never leave what you were doing.

| You type | What happens |
|---|---|
| `note buy new strings` | a new note in **Apple Notes** with that text |
| `remind me to call mom tomorrow at 5` | a reminder in **Apple Reminders**: "call mom", tomorrow 17:00 |
| `todo finish the report` | a reminder with no time, which is what a to-do is |
| `notes` or `note` on its own | a **glance** at the notes you made from the notch (below) |
| `reminders` or `reminder` on its own | a **glance** at what is coming up (below) |

Because these are Apple's own apps, everything syncs to your iPhone by itself. A reminder typed on the Mac buzzes your phone at the right time.

Before it closes, the notch shows what it understood (**call mom · Tomorrow 17:00**), so a misread never goes unnoticed.

**Times it understands**

| You say | It means |
|---|---|
| `in 20 minutes` · `in an hour` · `in half an hour` · `in 2 days` | that long from now |
| `today` · `tonight` · `tomorrow` · `day after tomorrow` | that day |
| `friday` · `on friday` · `next fri` | the coming Friday. If today is Friday, next week's. |
| `at 5pm` · `5:30 pm` · `18:30` · `at 06:15` | that time |
| `at 5` | 17:00. A bare hour from 1 to 6 means the afternoon. |
| `at 9` | 9:00 if that is still ahead today, otherwise 21:00 |
| `noon` · `midnight` · `in the morning` · `this afternoon` · `evening` | 12:00 · 0:00 · 9:00 · 15:00 · 19:00 |

- A day with no time means 9:00. `today` with no time, when 9:00 has already gone, means an hour or two from now.
- A time that has already passed today means tomorrow.
- Numbers that are not times are left alone: `watch 12 angry men`, `read chapter 5` and `buy 2 sets of strings` stay exactly as typed.

**The glance.** So nothing vanishes the moment the confirmation fades:

- `notes` shows the last six notes you made from the notch, newest first. Click one and Notes opens on that exact note. The buttons at the bottom make a **New note** or **Open Notes**.
- `reminders` shows up to six reminders that are not done yet, soonest first, from every list: ones you typed here, and ones made on your phone. **Click the circle** to tick one off (click again to undo). Click the words to open Reminders.
- The glance closes by itself after ten seconds, or press Escape.

Consigliere keeps its own short list of what you captured in `~/.consigliere/captures.json` (the last 50). The notes and reminders themselves live in Apple's apps, as always.

**Not yet:** calendar dates like "25 September" or "the 3rd". Say `in 4 days`, or open Reminders and set it there.

The first time, macOS will ask whether Consigliere may add to your Reminders and control Notes. Say yes once.

---

## 9½. Flipping the screen

**Status:** works on Adi's Mac, including with an HDMI screen connected (confirmed 9 Oct 2026) · uses a private part of macOS (see below)

Type `one eighty` (or `180`, `flip`, `rotate`, `upside down`). The screen turns upside down. Type it again to turn it back. You can also hold the talk key and say "one eighty".

It turns the laptop's own screen whenever the lid is open, even with an HDMI screen plugged in; with the lid closed it turns the external screen. There is no "are you sure?" step: if you did not mean it, say it again.

**With an HDMI screen plugged in.** There are several ways to ask macOS to rotate a screen, and one that works with the laptop alone can be quietly ignored once a second screen is connected. So Consigliere asks one way, watches whether the screen actually turned, and if not, asks the next way, up to three. It can take a second or two longer than usual. Only then does he speak. If you are *mirroring* (the same picture on both screens), macOS treats the pair as one screen; Consigliere tries that too, and if macOS still refuses he tells you to switch the HDMI screen to **Extended display** in System Settings → Displays.

If it ever fails, the notch says why, and the full story of the last attempt is in `~/.consigliere/flip.log`. To see it, paste this into Terminal on its own:

```
cat ~/.consigliere/flip.log
```

**How it works, and the catch.** macOS has no public way to rotate a screen. System Settings uses a private part of macOS (a framework called MonitorPanel), and Consigliere calls the same thing, the same way the open-source app Rotator does. Private means Apple can change it in any update: if `one eighty` stops working after a macOS update, that is why, and `App/Consigliere/ScreenRotator.swift` is the file to fix. If it fails, he tells you in the notch what went wrong.

While the screen is upside down the notch is at the bottom, so Consigliere appears as a small floating pill at the top of the laptop screen instead (it stays on the laptop even with an HDMI screen connected), and dragging onto the notch and clicking it do not work until you flip back. Everything you type still works, including `bored`.

---

## 10. Ask

**Status:** brain tested (recognising a question, what gets sent, splitting the answer) · working in the phone prototype through Claude itself · Mac app builds, never run · needs a Claude API key on the Mac

The box works like a browser's address bar. Type a name and it opens the thing. Type a question and it gets asked. There is nothing to switch and no command to learn.

**What counts as a question**

| You type | What happens |
|---|---|
| `how do i undo a git commit?` | asked. A question mark at the start or the end always means ask. |
| `what is a closure` · `why is my build failing` · `explain this` | asked. It starts with a question word. |
| `capital of italy` | asked. Several words that match nothing you have are treated as a question, but because he is less sure, he shows **Ask: capital of italy** and waits for Enter even when you spoke it. |
| `g how to tune a guitar` | **not** asked. Naming a site first still searches that site. |
| `what's app` | **not** asked. An exact name always wins. |

Before you press Enter, the row under the box says **Ask: …**, so you always know what Enter will do.

**The answer** appears in the notch as it is written: at most three short sentences, plain English. If the best answer is a command, it sits on its own line with a **Copy** button. The notch stays open until you dismiss it.

**"This" means what you copied.** Ask `explain this` or `what does this mean` and whatever you last copied (an error message, a line of code) is sent along. If your question does not say *this* or *these*, your clipboard is never sent.

**What it knows and does not know.** It answers from what the model already knows. It is very good at "how do I", "what is", "what does this error mean". It **cannot look things up**, so it does not know today's score, this week's news or current prices, and it is told to say so rather than guess. It can also simply be wrong, and a three-sentence answer has no sources. For anything that matters, check.

Looking things up live is possible later (Claude's API has a web search tool). It costs more per question and takes several seconds, so it is not in the first version.

**Cost and limits.** Each question is a fraction of a cent on the small fast model. Settings, under `ask` in the config:

- `model` — which Claude model answers.
- `maxTokens` — the longest reply allowed.
- `monthlyBudgetUSD` — a ceiling per month, default 2. When it is reached he says so and stops asking until next month.

The API key is stored in the Mac's Keychain, never in the config file. Questions are sent to Anthropic and nowhere else. Nothing is ever sent unless you press Enter on an **Ask** row.

**In the phone prototype** the same feature runs through your Claude account instead of an API key, so the first question asks your permission, and it may be a little slower than the Mac will be.

---

## 11. The voice

**Status:** brain tested (which line, how often, no repeats) · Mac app builds, never run

### What he says

Lines live in one file, `lines.json`. Each belongs to a category: opening a site, opening an app, saved, pulled, another, empty stash, unknown, timer done, all strings in tune, and so on.

Some things have their own lines. Open YouTube and you usually get a YouTube line; otherwise a general one. He never repeats any of the last five lines he used in a category.

**The rules every line follows:** eight words or fewer. About the task or about you, never about Italians. Never advice, never a question, never a comment on how long you have been doing something.

You can add, cut or rewrite lines by editing the file. Nothing else needs to change.

### How he sounds

Day one: a macOS **Italian** system voice reading the English text, which gives a thick accent for free. Better Italian voices can be downloaded in System Settings → Accessibility → Spoken Content.

Later, if you want: pre-made audio clips from a voice service. If a clip exists for a line, he plays it; otherwise he falls back to the system voice.

### How often

The text line **always** shows. Whether it is also *spoken* is a dial:

- `theme.voice.frequency` — 0 is never, 1 is every time. Default 0.6. The variety and this dial are what keep him funny after the hundredth time.
- `speak` — the master switch.
- **Mute** — right-click the notch. For class and the office.

---

## 12. Sounds and touch

**Status:** sounds made and playing in the phone prototype · the map of which sound goes with what is tested · Mac app builds, never run

Eight small sounds, all soft and glassy, none longer than a second. They are generated, not downloaded: the script that makes them is `scripts/make_sounds.py`, so any of them can be reshaped.

| Sound | When |
|---|---|
| open | the notch opens for typing |
| close | you dismiss it yourself. When it closes by itself after a line, it stays silent. |
| save | something goes into the stash, a note or reminder is made, a bookmark moves |
| pull | he hands something back, or you ask for another |
| nope | he does not know what you typed |
| answer | an answer has finished arriving |
| lock | a string comes into tune |
| done | the timer ends, or every string is in tune |

Opening a site or an app makes no sound. The thing appearing is the feedback.

**Touch:** the Mac's trackpad gives a small tap on open, on save, when a string locks and when the timer ends. You only feel it while a finger is resting on the trackpad, and it cannot be previewed on a phone.

Settings, under `feedback` in the config: `sounds` (on or off), `volume` (0 to 1), `haptics` (on or off). Muting the voice does not mute these, and the other way round.

---

## 13. Adding your own things

**Status:** brain tested · settings window in use on Adi's Mac

Everything he can open is an **entry**. You add entries in the settings window, so you never have to touch a file. Open it by typing `settings` in the notch, or by right-clicking the notch.

An entry has:

| Field | Meaning | Example |
|---|---|---|
| Name | what you type | `bat` |
| Other names | nicknames that also work | `batman` |
| Shown as | how it looks on screen | `Absolute Batman` |
| Opens | a web page, an app, or a folder | the chapter page |
| Brave profile | for web pages | `personal` |
| Search address | optional; makes `name words` search the site | `https://site/search?q={q}` |
| Remember where I left off | makes it a living bookmark (section 6) | on |

**Add the page I'm on** fills in the address from the tab you are looking at. You only type the name. That is how `bleach` becomes "open Bleach on Netflix" in five seconds.

**Apps.** You do not need an entry for an app at all: every app installed on this Mac (in Applications, Utilities, Apple's own apps, and `~/Applications`) opens by typing its name. `prime` finds Prime Video, `calc` finds Calculator. Your own entries always come first, and the things you open most rise to the top. To switch this off, untick **Every app on this Mac opens by name too** in settings.

Make an entry for an app when you want a nickname (`wa` for WhatsApp) or to fix which app a name opens. **Add an app** opens the usual file picker on your Applications folder: pick the app and Consigliere fills in everything, icon included. On an existing app entry, **Choose app…** swaps the app. You never need to know a "bundle identifier" again; if one in the config is wrong, Consigliere still finds the app by its name.

If a new name is exactly the same as one you already have, it warns you.

---

## 14. Look and feel

**Status:** chosen 25 September 2026 · builds · the phone prototype still shows the older Aurora look

The look is **Nocturne, liner notes**: the back of a CD booklet, at night. It was drawn from Adi's own desktop (the dark blue Deftones wallpaper with its beam of light), then stripped of anything cute.

- **The notch** stays black like the hardware. Along its bottom edge runs one thin line of steel-blue light, and a little film grain sits on its surface. A faint cold light surrounds it while it is open.
- **Type.** What matters is in thin Helvetica Neue, large, lowercase. Everything else (hints, where a thing opens, the tuning, "cents · tune up") is in small monospaced type, IBM Plex Mono, which ships inside the app.
- **Lists** read like a track list: `01 youtube ········ brave / personal`. The highlighted row gets a hairline of steel on its left edge, not a filled box. Rows are separated by hairlines.
- **His line** appears quietly after a dash, lowercase, in steel: `— it's done. don't ask how.`
- **The tuner** shows the note huge and thin; the needle is a short steel bar that turns white when the string is in tune. Strings already in tune turn steel.
- **The timer** is a big thin countdown over a thin steel bar.
- **Buttons** are outlines with a small monospaced label. There are no coloured fills anywhere.
- **One accent colour.** Everything that is not ink is the same steel blue.

What you can change without touching code, under `theme.look` in the config:

| Key | Default | What it does |
|---|---|---|
| `accent` | `#A9BBD6` (steel) | the one accent colour: the row marker, his line, the needle, the rim of light |
| `glowColors` | `#7890C8`, `#16233C`, `#0B1222` | the faint light around the open notch, inner to outer |
| `glowStrength` | `0.35` | 0 turns that light off |
| `grain` | `0.06` | how visible the film grain is; 0 turns it off |
| `textSize`, `caretBlinkMs` | `19`, `600` | base text size; cursor pulse |

The motion (`theme.motion.stiffness` and `damping`) is unchanged: the same spring as before.

A config written before this look (it has no `accent`) moves to it automatically the first time the new version starts. Text size and motion are kept.

On a screen with no notch (an external monitor, or while the screen is flipped), it appears as a small floating pill at the top centre. The settings window stays a normal Mac window.

---

## 15. Hotkeys

**Status:** written into the app · never run · you may well change them on the Mac

| Hotkey | Does | Default | Config key |
|---|---|---|---|
| Open | opens the box in the notch; press again to close it | `opt+space` (⌥Space) | `hotkeys.open` |
| Talk | hold to talk, release to run | `ctrl+opt+space` (⌃⌥Space) | `hotkeys.talk` |
| Save | saves the front browser page to the stash | `ctrl+opt+s` (⌃⌥S) | `hotkeys.save` |
| Mark my place | moves a living bookmark to the page in front | `ctrl+opt+m` (⌃⌥M) | `hotkeys.mark` |

Write them as modifiers joined by `+`, ending in a normal key: `cmd`, `opt`, `ctrl`, `shift`, then a letter, a digit, `space`, `return` and so on. **A modifier on its own cannot be a hotkey on a Mac** (so "just the right Option key" is not possible); there must be a normal key at the end.

Change them by typing `settings` in the notch → **Hotkeys and files**. They take effect when you press Save.

Inside the open notch: **Enter** runs the highlighted row, **↑ ↓** move the highlight, **Escape** closes, and so does a click anywhere else.

**Right-click the notch** for a small menu: Settings, Mute him, Cancel the timer (when one is running), Quit.

**The tutorial.** Three slides that cover everything: they show once the first time Consigliere starts, and after that whenever you type `help`, or press the **?** at the bottom of the settings window. The hotkeys on the slides are whatever yours are set to.

---

## 16. The config file, key by key

`~/.consigliere/config.json`. It is created with sensible defaults the first time the app runs. **Every key is optional**: leave one out and the default is used. If you make a typo that breaks the file, the app uses defaults for that run and **leaves your file alone**, so a mistake never wipes your settings.

```json
{
  "hotkeys": { "open": "opt+space", "talk": "ctrl+opt+space", "save": "ctrl+opt+s", "mark": "ctrl+opt+m" },
  "brave": {
    "binaryPath": "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "personalProfileDir": "Default",
    "workProfileDir": "Profile 1"
  },
  "speak": true,
  "speechLocale": "en-IN",
  "theme": {
    "motion": { "stiffness": 260, "damping": 24 },
    "look":   { "palette": "nocturne", "accent": "#A9BBD6", "glowColors": ["#7890C8", "#16233C", "#0B1222"], "glowStrength": 0.35, "grain": 0.06, "textSize": 19, "caretBlinkMs": 600 },
    "voice":  { "voiceName": "", "rate": 0.95, "pitch": 0.9, "frequency": 0.6 }
  },
  "tuner": { "a4": 440, "toleranceCents": 5, "lastTuningID": "guitar-standard", "customTunings": [] },
  "ask":   { "model": "claude-haiku-4-5", "maxTokens": 300, "monthlyBudgetUSD": 2 },
  "feedback": { "sounds": true, "volume": 0.5, "haptics": true },
  "includeInstalledApps": true,
  "jobs": { "dayStart": "09:00", "bedtime": "00:30", "cooldownMinutes": 45, "laterMinutes": 30, "maxLevel": 3, "roamMinutes": 3, "openListAt": "10:00", "bindings": {} },
  "character": { "folder": "~/.consigliere/character", "size": 64, "roam": false, "facesLeft": false },
  "music": { "player": "spotify" },
  "catalog": [ ]
}
```

| Key | Meaning |
|---|---|
| `hotkeys.*` | see section 15 |
| `brave.binaryPath` | where Brave lives. Only change it if you installed Brave somewhere unusual. |
| `brave.personalProfileDir`, `brave.workProfileDir` | the folder names Brave uses for your two profiles. Found on day one. |
| `speak` | master switch for the voice |
| `speechLocale` | the accent the Mac should expect when you talk to it. `en-IN` is English as spoken in India; try `en-US` or `en-GB` if it mishears you. |
| `theme.motion.stiffness` | how hard the notch snaps open. Higher is snappier. |
| `theme.motion.damping` | how quickly it settles. Lower is bouncier. |
| `theme.look.accent` | the one accent colour (section 14) |
| `theme.look.glowColors` | the three colours of the faint light around the open notch, `#RRGGBB`, inner to outer. An unreadable one falls back to the default. |
| `theme.look.grain` | film grain on the notch, 0 to 1 |
| `theme.look.glowStrength` | 0 is no glow, 1 is full |
| `theme.look.textSize`, `caretBlinkMs` | base text size in points; how long one cursor pulse takes |
| `theme.voice.voiceName` | which system voice. Empty means the best Italian one installed. |
| `theme.voice.rate`, `pitch` | 1.0 is the voice's normal speed and pitch |
| `theme.voice.frequency` | 0 to 1, how often lines are spoken as well as shown |
| `tuner.*` | see section 7 |
| `ask.*` | see section 10 |
| `feedback.*` | see section 12 |
| `includeInstalledApps` | every installed app opens by name without an entry (section 13) |
| `jobs.*` | when he comes out about jobs, and what words open what (section 20) |
| `character.*` | where his pictures are, how big he is, whether he may fly out (section 21) |
| `music.player` | `spotify` or `music` (Apple Music) (section 23) |
| `catalog` | your entries (section 13). One entry looks like this: |

```json
{ "name": "bat", "display": "Absolute Batman", "aliases": ["batman"], "kind": "site",
  "target": "https://…", "profile": "personal", "living": true }
```

`kind` is `site`, `app`, `path` or `tool`. For an app, `target` is its bundle identifier (for example `com.valvesoftware.steam`). For a folder, it is the path (`~/Downloads`). `tool` is for built-in things: `tuner`, `timer`, `note`, `reminder`, `flip`, `help`, `pull` (what `bored` runs), `settings`, `jobs`, `done`, `diary`, `quiet`, `music`, `playpause`, `next`, `louder`, `quieter` and `volume`.

---

## 17. Where your files live

| File | What it holds |
|---|---|
| `~/.consigliere/config.json` | every setting and every entry |
| `~/.consigliere/usage.json` | how often you open each thing, for tie-breaking |
| `~/.consigliere/line-state.json` | which lines he used recently, so he does not repeat |
| `~/.consigliere/captures.json` | the last 50 notes and reminders made from the notch, for the glance |
| `~/.consigliere/jobs.json` | today's jobs: what is done, skipped, still owed, and when he last came out |
| `~/.consigliere/character/` | your own pictures for the character, if you have any (section 21) |
| iCloud Drive `/Consigliere/stash.json` | the stash. If iCloud Drive is off, it lives in `~/.consigliere/` instead. |
| iCloud Drive `/Shortcuts/Consigliere/` | the three small text files the iPhone shortcuts and the Mac pass back and forth (`docs/IPHONE.md`) |

All plain text. You can open, read and back up any of them. If the stash file is ever damaged (a half-finished sync, say), the app moves it aside under a new name and starts a fresh one. **It never deletes it.**

---

## 18. When something goes wrong

This section will grow once the app has actually run. What can already be predicted:

| Problem | Likely cause | Fix |
|---|---|---|
| A site opens in the wrong Brave profile | the profile folder names in the config are wrong | find the real names (DAY_ONE.md) and set `brave.personalProfileDir` / `workProfileDir` |
| Hold-to-talk does nothing | microphone or speech permission was refused | System Settings → Privacy & Security → Microphone, and Speech Recognition |
| Save hotkey does nothing | macOS blocked Consigliere from asking Brave for its tab | System Settings → Privacy & Security → Automation → allow Consigliere to control Brave |
| The voice is not Italian | no Italian voice installed | System Settings → Accessibility → Spoken Content → System Voice → Manage Voices → Italian |
| Settings seem ignored after you edited the file | a typo broke the file, so defaults are in use | fix the typo. Your file was not touched. |
| The tuner is jumpy on the lowest string in Drop B or Drop A | laptop microphones are weak at those pitches | pluck closer to the laptop, or tune that string by ear from the one above |

---

## 19. What is built and what is not

| Piece | State |
|---|---|
| Matcher, stash, line picker, tuner maths, timer, living bookmarks, iPhone sync, reading reminders, asking | **Built and tested in JavaScript** (36 tests) |
| The same, in Swift | **Compiles and passes all 41 tests on GitHub's cloud Mac** |
| Phone prototype (notch feel, typing, stash, tuner, voice preview) | **Working** |
| Cloud-Mac build and test workflow | **Running on every push.** First run all green. |
| The Mac app: notch, hotkeys, opening things, drag to save, voice, sounds, settings window, tuner, timer, notes and reminders, hold-to-talk, Ask | **Runs on Adi's MacBook** (first launch 25 September 2026). Built and tested on every push by GitHub's cloud Mac. |
| Ask | **Brain built and tested; works in the phone prototype.** On the Mac it answers all at once rather than word by word. |
| Full line bank | **243 lines written**, in `defaults/lines.json`. Edit freely. |
| Saving from the iPhone, and Bored on the iPhone | **Mac-side logic built and tested.** The two shortcuts are written up step by step in `docs/IPHONE.md` and have not been built on a real phone yet. |
| The look (first) | Aurora, in the phone prototype. Replaced on the Mac by Nocturne. |
| Interface sounds | **Made** (eight WAV files, generated by a script). Playing in the phone prototype. |
| Round two (25 Sep 2026) | Timer screen with Stop and more time · glance at notes and reminders · every installed app opens by name · app picker in settings · flipping the screen · three-slide tutorial · one-command updates (`scripts/install.sh`). All build; not yet tried on the Mac. |
| The look | **Nocturne, liner notes**, chosen and built (section 14). |
| Version 2 (11 Oct 2026) | Jobs with starters, the character who flies out, the diary, music by name (sections 20 to 23). Brain built and tested in JavaScript and Swift; the app builds. **Not yet run.** |

Ideas that are parked, not planned: a calculator in the box (so sums never go to the AI), Look (drag a box on the screen and ask about it), finding saved things by meaning, a hook so your own scripts can make him announce things, cheat codes, a metronome, screenshots into the stash, running your own Shortcuts by name, a live football score in the notch, silent "idle" cards (a chord shape, a line of Python) in the closed notch.

---

## 20. Jobs

**Status:** brain tested (reading jobs, what opens each one, when he comes out, carrying jobs over) · in daily use on Adi's Mac since 12 Oct 2026

The day's to-do list, the family-business way: they are **jobs**. The thing that makes this one different from a diary is that every job knows **what to open**. You never have to go and find the book or the course: **start** opens it.

**Type `jobs`** and the checklist opens in the notch:

- **Add** by typing in the line at the bottom and pressing Enter. Commas add several at once (`read 30 min, gym, duolingo by 10pm`). The line stays ready for more.
- **Tick** a box and the job is done, with a small pixel explosion and a sound. Tick it again if you did it by mistake.
- **start** (on jobs that know what to open) opens it and starts the timer for the job's length.
- **Right-click** a job to delete it.
- **Escape**, or a click anywhere else, closes the list.

**Every day from 10:00** the list opens by itself, the first time you are at the Mac after that (not while a Focus mode with his filter is on, and not after `quiet`), so the day starts with a look at what is on the books. It opens without taking the keyboard, so nothing you are typing lands in it; click the line at the bottom to add. Untouched, it closes after a minute. Change the time with `jobs.openListAt` (empty: never).

Shortcuts from the box, if you prefer them:

| You type | What happens |
|---|---|
| `jobs read 30 min, swift course` | adds them without opening the list. He says back what he understood. |
| `done read` | that job is done. `done` on its own finishes the one you started. |
| `quiet` (or `hush`, `leave me alone`) | he stays in the notch until tomorrow |

- **Commas** separate jobs. "and" does not, so `call mom and dad` is one job.
- **How long**: `30 min`, `for an hour`, `half an hour`, `1.5h`. Starting the job starts a timer that long; when it ends he asks *done?*
- **When**: `by 10pm`, `at 6`, `in 20 minutes`: the same times reminders understand (section 9).
- Saying the same job again (`read 45 min`) updates it instead of adding a second one.

**What starts a job.** He looks for one of your things in the job's words: `read` opens Books, `duolingo` opens Duolingo, `finish the swift course` opens your entry called `swift course` (make it a living bookmark, section 6, and it opens where you stopped). If nothing fits, **start it** opens the box and asks *what opens "practice guitar"?*: whatever you open next becomes that job's starter, and the first word is remembered (`practice` → that thing) for every later job. These learned words live under `jobs.bindings` in the config.

**Owed.** A job you did not finish moves to tomorrow, owed one more day. Nothing is lost, and nothing counts a streak; it just says *owed 3 days*, and he lets you know about it.

**The day** runs from 04:00 to 04:00, so a job typed at one in the morning belongs to the evening before.

## 21. The character

**Status:** in use on Adi's Mac since 12 Oct 2026 (`pet`, the head beside the notch, a custom GIF) · the timing of when he comes out is brain tested

He lives in the notch: he sits beside his lines when the notch opens. **Whenever a job is due, he sits beside the closed notch**, staring out, until it is done, started, skipped or put off. Click him for the list. That is the whole reminder: **he never flies out of the notch for a job** (Adi, 29 October 2026). The old "He may fly out" switch is gone, and `character.roam` in the config is ignored.

A job is due when it is not ticked, not started, not put off with **later**, and either has no time or its time has passed (`gym by 7pm` waits until 7pm). He checks every 30 seconds.

**Playing with him.** Type `pet` (or `dragonite`, `come here`, or click him at the top of the jobs list) and he flies out of the notch to wander around the screen. Then:

| You | He |
|---|---|
| rub the mouse over him | pixel hearts float up, he wiggles, and now and then says something (in a speech bubble, and out loud) |
| click him | hops, one heart |
| drag him and let go fast | gets thrown: tumbles, bounces off the edges of the screen, sees stars, rights himself, grumbles |
| right-click → **Follow me** | chases your cursor for twenty seconds |
| right-click → **Fetch**, then click anywhere | flies to where you clicked (the click also lands on whatever is there) |
| right-click → **Go home**, or type `go home` (`go back`, `go away`, `back off`, `scram`, `bye`) | says goodbye and flies back into the notch |

He never lingers: left alone for 12 seconds he flies home by himself, and after 45 seconds out he goes home whatever he is doing. Typing `pet` while he is out brings him over to the cursor. `go home` works when he is out about a job too: it means "not now", like closing his card, and does not count as ignoring him. He talks only right after something you did to him. You can drag and pet him when he is out about a job too; a click then opens the job card as usual.

**Your own character.** Put pictures in `~/.consigliere/character/`: an **animated GIF** called `idle.gif` (plus `fly.gif` if flying should look different), or numbered PNGs `idle_0.png`, `idle_1.png`… and `fly_0.png`…. Any one GIF, or any PNGs, in the folder also work. A GIF plays at its own speed. Most game sprites face left: tick **The pictures face left** in settings (`character.facesLeft`) so he turns the right way when he flies. Pixel art stays sharp. Press **Save** in settings (or restart) to load them.

On Adi's Mac the folder holds **Gengar in a mafia fedora**: Gengar's animated sprite from Pokémon Black and White (Pokémon Showdown's sprite collection, `play.pokemonshowdown.com/sprites/gen5ani/gengar.gif`), with a pixel fedora put on every frame by `scripts/hat.py`:

```
python3 scripts/hat.py gengar.gif ~/.consigliere/character/idle.gif
```

The script finds the top of his head in each frame, so the hat follows him as he moves; it works on other characters too (tweak `SINK` if it sits too high or low). Dragonite, the one before, is kept in `~/.consigliere/characters-retired/`. Without a folder he is the little orange dragon that ships with the app. Art that belongs to someone else (a Dragonite) stays in that folder and never goes into the repo.

Settings: **settings → Jobs and music**: the character folder, his size, and which way the pictures face (`character.folder`, `character.size`, `character.facesLeft`).

## 22. The diary

**Status:** Mac app builds, never run

- `diary long day, good one` adds a line, with the time, to **one Apple Notes note per day** ("Consigliere diary · 11 Oct 2026").
- `diary` on its own opens today's.
- When you tell him **going** at bedtime, the day's jobs (done, skipped, still owed) are written into the same note. That is the whole record: no charts.

## 23. Music

**Status:** works on Adi's Mac with Spotify (11 Oct 2026) · Apple Music not yet tried · Spotify needs a free key to play rather than search

| You say or type | What happens |
|---|---|
| `play beabadoobee` · `music beabadoobee` · `lofi music` | plays it |
| `pause` (or `resume`) | pauses or carries on |
| `next` · `skip` | next song |
| `louder` · `quieter` · `volume up` | the Mac's volume, by a tenth |
| `volume 30` | the Mac's volume, out of 100 |

`play me some youtube` still opens YouTube: *play* only means music when what follows is not one of your things.

**Spotify** can only be told to play something it has an address for, and finding the address from words needs Spotify's search. That needs a free key: **developer.spotify.com → Dashboard → Create app**, then paste the **Client ID** and **Client secret** into **settings → Jobs and music**. They are kept in the Keychain. Without them, `play beabadoobee` opens Spotify's search for it, one click short.

**Apple Music**: set **Music plays in** to Apple Music. It searches your library and plays the first match. No key needed.

The first time, macOS asks whether Consigliere may control Spotify (or Music). Say yes once.

**If it does not play**, the notch says why, and `cat ~/.consigliere/music.log` shows every step of the last try (never the keys). "Invalid client secret" there means the secret in settings is wrong: copy it again from the dashboard (**View client secret**) and paste it into an empty box.

---

## Updating to a new version

When new code is ready, one command does everything: gets it, builds it, signs it, replaces the app in Applications and starts it. New built-in commands (like `flip`, `settings`, `help` and `bored`, all added after the first release) are added to your config automatically the next time Consigliere starts after an update. If you had deliberately deleted one of them in Settings, it stays deleted; only genuinely new commands get added.

```
~/Code/consigliere/scripts/install.sh
```

The first time takes a few minutes; after that about a minute. If you added your Apple ID in Xcode (Settings → Accounts), the app is signed the same way every time and macOS keeps its permissions between updates. Without it, macOS may ask for the microphone and the other permissions again after an update.
