# Consigliere on the iPhone

**Status:** designed, never run. The Mac-side logic that reads these files is built and tested. The two shortcuts below have not been built on a real iPhone yet, and Apple renames Shortcuts actions between iOS versions, so expect one or two steps to be worded differently on your phone. Tell me which and I will fix this page.

## What you get

Two shortcuts. No app, no App Store, no developer account, nothing to pay for.

1. **Save to Consigliere** sits in the share sheet. Share a link, a page or some text to it, and it is saved. It asks you nothing.
2. **Bored** gives you back one thing you saved, and he says a line in the Italian voice.

They work **with a Mac** (things saved on the phone show up in the Mac's stash, and things saved on the Mac come back on the phone) and **without one**. So someone with only an iPhone gets a complete save-and-get-back tool from these two shortcuts alone. Each person's stash lives in their own iCloud, so yours and hers never mix.

## How it avoids losing things

iCloud gets confused when two devices write to the same file. So no file here is ever written by two devices:

| File (in iCloud Drive → Shortcuts → Consigliere) | Who writes it | What is in it |
|---|---|---|
| `phone-inbox.txt` | only the phone | one save per line: date, a space, the link or text |
| `phone-opened.txt` | only the phone | one line each time Bored opens something |
| `for-phone.txt` | only the Mac | everything unopened in the Mac's stash, one per line |

The Mac reads the first two and folds them into its stash. It can do this over and over without ever creating a duplicate. It never edits the phone's files.

---

## Shortcut 1: Save to Consigliere

Open the **Shortcuts** app → **+** → name it `Save to Consigliere`.

Tap the **ⓘ** at the bottom → turn on **Show in Share Sheet**. Back in the editor, the first block now says *Receive … input from Share Sheet*. Tap the input types and keep only **URLs**, **Safari web pages**, **Articles** and **Text**. Where it says *If there's no input*, choose **Get Clipboard** (so it also works when you run it from the Home Screen).

Then add these actions in order. Search for each by name.

| # | Action | Settings |
|---|---|---|
| 1 | **Get URLs from Input** | Input: *Shortcut Input* |
| 2 | **If** | *URLs* **has any value** |
| 3 | &nbsp;&nbsp;**Get Item from List** | *First Item* from *URLs* |
| 4 | &nbsp;&nbsp;**Set Variable** | Name `Thing`, to *Item from List* |
| 5 | **Otherwise** | |
| 6 | &nbsp;&nbsp;**Replace Text** | Find `\s*\n\s*`, replace with a single space, in *Shortcut Input*. Tap **Show More** and turn on **Regular Expression**. (This keeps a saved paragraph on one line.) |
| 7 | &nbsp;&nbsp;**Set Variable** | Name `Thing`, to *Updated Text* |
| 8 | **End If** | |
| 9 | **Current Date** | |
| 10 | **Format Date** | Date Format: **ISO 8601**. Turn on **Include ISO 8601 Time**. |
| 11 | **Text** | *Formatted Date*, one space, then the variable *Thing* |
| 12 | **Append to Text File** | Append *Text*. Folder: **Shortcuts**. File Path: `Consigliere/phone-inbox.txt`. **Make New Line** on. |
| 13 | **Show Notification** | `Safe with me.` |

Test it: open Safari, tap Share, pick **Save to Consigliere**. Then in the **Files** app look in iCloud Drive → Shortcuts → Consigliere. You should see `phone-inbox.txt` with one line in it that starts with today's date.

The voice is left out of this one on purpose. Share-sheet shortcuts get very little time to run, and a notification is instant.

---

## Shortcut 2: Bored

**+** → name it `Bored`.

| # | Action | Settings |
|---|---|---|
| 1 | **Get File from Folder** | Folder: **Shortcuts**. Path `Consigliere/phone-inbox.txt`. Turn **off** *Error If Not Found*. |
| 2 | **Set Variable** | Name `Inbox`, to *File* |
| 3 | **Get File from Folder** | Path `Consigliere/for-phone.txt`. *Error If Not Found* **off**. |
| 4 | **Set Variable** | Name `FromMac`, to *File* |
| 5 | **Get File from Folder** | Path `Consigliere/phone-opened.txt`. *Error If Not Found* **off**. |
| 6 | **Text** | the *File* from step 5, then a space. (The space stops the next steps tripping over an empty file.) |
| 7 | **Set Variable** | Name `Opened`, to *Text* |
| 8 | **Text** | variable *Inbox*, a new line, variable *FromMac* |
| 9 | **Split Text** | by **New Lines** |
| 10 | **Repeat with Each** | item in *Split Text* |
| 11 | &nbsp;&nbsp;**Replace Text** | Find `^\d{4}-\d{2}-\d{2}\S*\s+`, replace with nothing, in *Repeat Item*. **Regular Expression** on. (This strips the date off the front.) |
| 12 | &nbsp;&nbsp;**If** | *Updated Text* **has any value** |
| 13 | &nbsp;&nbsp;&nbsp;&nbsp;**If** | *Opened* **does not contain** *Updated Text* |
| 14 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**Add to Variable** | add *Updated Text* to `Candidates` |
| 15 | &nbsp;&nbsp;&nbsp;&nbsp;**End If** | |
| 16 | &nbsp;&nbsp;**End If** | |
| 17 | **End Repeat** | |
| 18 | **If** | *Candidates* **has any value** |
| 19 | &nbsp;&nbsp;**Get Random Item from List** | from *Candidates* |
| 20 | &nbsp;&nbsp;**Set Variable** | Name `Pick`, to *Random Item* |
| 21 | &nbsp;&nbsp;**Current Date** → **Format Date** | ISO 8601 with time, as in the first shortcut |
| 22 | &nbsp;&nbsp;**Text** | *Formatted Date*, one space, *Pick* |
| 23 | &nbsp;&nbsp;**Append to Text File** | to `Consigliere/phone-opened.txt`, **Make New Line** on |
| 24 | &nbsp;&nbsp;**List** | five or six lines, one per row: `From the vault, for you.` · `This one, you liked.` · `You got good taste, you know.` · `An oldie. A goodie.` · `I kept this warm for you.` · `Tonight's special.` |
| 25 | &nbsp;&nbsp;**Get Random Item from List** | from *List* |
| 26 | &nbsp;&nbsp;**Speak Text** | the random line. Tap **Show More**: Language **Italian (Italy)**, pick a voice, **Wait Until Finished** on. |
| 27 | &nbsp;&nbsp;**If** | *Pick* **begins with** `http` |
| 28 | &nbsp;&nbsp;&nbsp;&nbsp;**Open URLs** | *Pick* |
| 29 | &nbsp;&nbsp;**Otherwise** | |
| 30 | &nbsp;&nbsp;&nbsp;&nbsp;**Show Alert** | *Pick* (it was a note, not a link) |
| 31 | &nbsp;&nbsp;**End If** | |
| 32 | **Otherwise** | |
| 33 | &nbsp;&nbsp;**Speak Text** | `The vault is empty, boss.` Same Italian voice. |
| 34 | **End If** | |

On the phone he speaks *before* the link opens, which is the opposite of the Mac. That is deliberate: once Safari comes to the front, a shortcut's speech tends to get cut off.

### The best way to trigger it

Settings → Accessibility → Touch → **Back Tap** → **Double Tap** → choose **Bored**. Now two taps on the back of the phone hands you something you saved. No app to open. If your iPhone has an Action Button, that works too.

You can also add it to the Home Screen from the shortcut's share menu.

---

## What the phone version does not do

- There is no "another" that puts the last one back. Run **Bored** again and you simply get the next thing; the one before stays marked as opened.
- It picks at random. The Mac's smarter rule (alternate fresh and old, push skipped things to the back) only runs on the Mac.
- The same link saved on both devices can show up twice in the phone's pool for a short while, until the Mac has folded the phone's inbox in. Harmless: it just makes that link slightly more likely to be picked.
- It saves links and text. Not images or files.

## Giving it to someone else

In the Shortcuts app, long-press a shortcut → **Share** → **Copy iCloud Link**, and send the link. (If the option is missing: Settings → Shortcuts → turn on **Private Sharing**.) They tap it, add it, and they are done. Their stash is theirs alone. Without a Mac, `for-phone.txt` simply never exists, and everything else works the same.

## On the Mac side

Nothing to set up. When the Mac app runs it looks for this folder, folds `phone-inbox.txt` and `phone-opened.txt` into the stash, and rewrites `for-phone.txt` whenever the stash changes. If the folder is not there (you never made the shortcuts), it does nothing and creates nothing.
