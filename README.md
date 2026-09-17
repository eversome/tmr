# tmr

A countdown timer for macOS that runs in the terminal, in a floating window, or
on a BUSY Bar - from the same command.

```
tmr 5m
tmr -t 25m -n focus
tmr -u -a -t 1m
```

Status: **v0.1** - core, terminal view and sound. The window (`-u`) and the
BUSY Bar output (`-b`) are on the roadmap below.

## Install

Not on Homebrew yet. Build it:

```sh
swift build -c release
cp .build/release/tmr /usr/local/bin/
```

Requires macOS 13+ and Xcode 15 / Command Line Tools.

## Usage

```
tmr [<timespec>] [options]

  -t, --time <spec>      Duration, same syntax as the positional argument
  -n, --name <name>      Name shown above the countdown
  -u, --ui               Floating window (v0.2)
  -a, --alert [<sound>]  Alert sound: a name from /System/Library/Sounds,
                         or a path. Bare -a uses Glass.
  -s, --silent           No sound
      --ring             Keep ringing until a key is pressed
  -q, --quit-after <n>   Quit n seconds after the countdown ends
      --list-sounds      Print the available sounds and exit
```

Durations accept `90` (seconds, like `sleep`), `5m`, `1h30m`, `1h 5m 30s`,
`1.5m`, `25:00` and `1:02:03`.

Keys while a timer runs: `space` pause, `+` / `-` one minute, `r` reset,
`q` quit. Any key dismisses a ringing timer.

When stdout is not a terminal the view degrades to two plain lines, so
`tmr 10m && say done` and Raycast script commands behave.

## Design

```
Sources/
  TimerCore/    pure logic: duration parsing, state machine. No I/O, no AppKit.
  Renderers/    terminal view, sound. The window and the bar land here.
  tmr/          argument parsing and the render loop.
```

`TimerCore` never reads a clock of its own - the caller passes `now` into
`update(now:)` and `snapshot(now:)`. That is what makes the tests exhaustive and
instant, and it is what will let the terminal, the window and the bar render the
same timer without drifting apart.

## Roadmap

- **v0.1** core, terminal view, sound
- **v0.2** `-u`: borderless always-on-top HUD with a progress ring
- **v0.3** Raycast script command
- **v0.4** `-b`: BUSY Bar output over its HTTP API (72x16 main display, 160x80
  back display), `--bar-host` for the emulator
- **v0.5** Homebrew tap, universal binary, signed releases

## License

MIT
