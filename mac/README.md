# Third Timer for Mac

A menu bar app for the Third Time method: work as long as you like, and
earn break time in proportion. See the spec in issue #1.

## Install

You need a Mac on macOS 13 or later, with Xcode or the Xcode Command Line
Tools (`xcode-select --install`).

```sh
git clone https://github.com/florian42/thirdTimer.git
cd thirdTimer
git checkout claude/eloquent-gates-034sfi
./mac/install.sh
```

The script builds the app, copies it to `/Applications/ThirdTimer.app` and
starts it. It appears in the menu bar as `⏸ Idle`. There is no Dock icon.

To start it at every login, open the panel, then Settings, then turn on
"Start at login".

## Use

- **Control-Option-T** toggles from anywhere: start working, take a break,
  resume work.
- Click the menu bar item for the panel: deliverables, partial breaks, the
  break ratio, checkpoints, the hand-off note, working hours.
- The menu bar shows `🟢 Report · 34m` while you work and
  `🔵 Break · 6:12 left` on a break.

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

- `--window` also shows the panel in an ordinary window.
- `--demo working`, `--demo breaking` or `--demo ending` starts from a sample
  session. This replaces the saved state, so set `THIRDTIMER_STATE_FILE` too.
- `--print-title` prints the menu bar text once a second.
- `THIRDTIMER_STATE_FILE=/path/state.json` uses a different state file.
