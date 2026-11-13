# Third Timer for Mac

A menu bar app for the Third Time method: work as long as you like, and
earn break time in proportion. See the spec in issue #1.

## Install

You need a Mac on macOS 13 or later, with Xcode or the Xcode Command Line
Tools (`xcode-select --install`).

```sh
git clone https://github.com/florian42/thirdTimer.git
cd thirdTimer
./mac/install.sh
```

The script builds the app, copies it to `/Applications/ThirdTimer.app` and
starts it. It appears in the menu bar as `Idle` with a pause symbol. There is no Dock icon.

To start it at every login, open the panel, then Settings, then turn on
"Start at login".

## Use

- **Meetings pause the timer by themselves.** The app reads the Mac's
  calendars (macOS asks for permission once). While an event covers the
  current time, the timer is paused and nothing rings or pops up; when it
  ends, work starts again on the same deliverable. All-day entries, time
  marked as free, and declined or cancelled invitations don't count. Turn it
  off under Settings, "Pause during calendar meetings".
- **Pause timer** does the same by hand: it stops the timer for anything that is neither work on
  a deliverable nor a break. Nothing is earned or spent, banked break time is
  kept, and the bell stays quiet until you go back to work.
- **Control-Option-T** toggles from anywhere: start working, take a break,
  resume work.
- Click the menu bar item for the panel: what you're working on, partial
  breaks, checkpoints, the hand-off note and settings.
- The menu bar shows `Report · 34m` while you work and `Break · 6:12 left`
  on a break, each with its own symbol.
- After an hour of unbroken work a soft bell suggests a pause. It waits for a
  lull in your typing, and "Not now" hides it until the next one.
- At noon it suggests lunch: a longer break that starts the afternoon with an
  empty bank.
- Settings change the break ratio, when a pause and lunch are suggested, and
  whether the bell rings.

The reasoning behind these defaults is in `docs/research/breaks.md`.

State is saved in `~/Library/Application Support/ThirdTimer/state.json`.

## Layout

- `Sources/ThirdTimerCore`: the session engine. Every rule of the method,
  as a pure function of state, event and time.
- `Sources/ThirdTimer`: the Mac shell. Menu bar item, panel, hotkey, alarm,
  state file.
- `Tests/ThirdTimerCoreTests`: tests of the engine.

## Develop

```sh
cd mac
swift test          # engine tests (needs Xcode, not only the Command Line Tools)
./build-app.sh      # builds build/ThirdTimer.app
```

Flags for checking the app by hand or in CI:

- `--walkthrough` plays a scripted day of use with captions and a fast clock.
  A recording of it is in `docs/walkthrough.mp4`.
- `--window` also shows the panel in an ordinary window.
- `--demo working`, `breaking`, `ending`, `worst`, `idle`, `nudge`, `noon` or
  `lunch` starts from a sample session. This replaces the saved state, so set `THIRDTIMER_STATE_FILE` too.
- `--print-title` prints the menu bar text once a second.
- `--at 12:05` sets the app's clock to that time today.
- `THIRDTIMER_STATE_FILE=/path/state.json` uses a different state file.
