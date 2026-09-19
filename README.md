# tmr

A countdown timer for macOS that runs in the terminal, in a floating window, or
on a BUSY Bar - from the same command.

```
tmr 5m
tmr -t 25m -n focus
tmr -u -a -t 1m
```

Status: **v0.4** - core, terminal view, floating window, sound, Raycast, BUSY Bar.

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
  -n, --name <name>      Name shown next to the countdown
  -u, --ui               Floating window: ring, digits, hover controls
  -a, --alert [<sound>]  Alert sound: a name from /System/Library/Sounds,
                         or a path. Bare -a uses Glass.
  -s, --silent           No sound
      --ring             Keep ringing until a key is pressed
  -q, --quit-after <n>   Quit n seconds after the countdown ends
      --list-sounds      Print the available sounds and exit
  -b, --bar              Also show the countdown on a BUSY Bar
      --bar-host <addr>  Bar address (default 10.0.4.20, the USB one)
      --bar-token <key>  Bar access key, needed over Wi-Fi only
      --bar-sound <name> Stock sound the bar plays at the end, or 'none'
      --list-bar-sounds  Print the bar's stock sounds and exit
```

Durations accept `90` (seconds, like `sleep`), `5m`, `1h30m`, `1h 5m 30s`,
`1.5m`, `25:00` and `1:02:03`.

Keys while a timer runs: `space` pause, `+` / `-` one minute, `r` reset,
`q` quit. Any key dismisses a ringing timer. In the window the same actions sit
under the pointer, and anywhere else drags it.

When stdout is not a terminal the view degrades to two plain lines, so
`tmr 10m && say done` and Raycast script commands behave.

## Raycast

The scripts in `raycast/` are Raycast Script Commands - no extension to build.
In Raycast, open Extensions, add a Script Directory and point it at the folder:

- **Start Timer** - duration plus an optional name, opens the floating window
- **Stop Timers** - stops everything that is running

They look the binary up in /usr/local/bin, /opt/homebrew/bin and ~/.local/bin,
because Raycast runs scripts with a minimal PATH.

## BUSY Bar

`-b` adds the bar as a third output, alongside the terminal or the window. The
countdown goes on the front 72x16 matrix, the timer's name and its finish time
on the back panel, and the zeros blink there until the timer is dismissed.

```sh
tmr -b 25m                              # over USB
tmr -b --bar-host 192.168.1.20 25m      # over Wi-Fi
tmr -b -u --bar-sound completed 25m     # window and bar together
```

The end-of-timer sound is one the firmware already ships, played by stock path,
so nothing is uploaded to the device: `event`, `reminder`, `volume`, `tick`,
`finish` (the default), `completed`. Uploading your own needs the device's audio
format, which is not documented, so it waits for v0.4.1.

The engine ticks at 12 fps but the bar is behind an HTTP round trip, so
`BarRenderer` sends at most twice a second, only on a real change, and never
queues a second request behind the first. Everything drawn belongs to the
`tmr` application name and is cleared on exit, Ctrl-C included.

## Design

```
Sources/
  TimerCore/    pure logic: duration parsing, state machine. No I/O, no AppKit.
  Renderers/    terminal view, floating window, sound. The bar lands here.
  tmr/          argument parsing, session policy, drivers.
```

`TimerCore` never reads a clock of its own - the caller passes `now` into
`update(now:)` and `snapshot(now:)`. That is what makes the tests exhaustive and
instant, and it is what lets the terminal, the window and the bar render the
same timer without drifting apart.

`SessionPolicy` holds what a keypress means and when the process should exit, so
the terminal and the window cannot drift apart in behaviour.

## Development

```sh
swift build
swift test
```

The tests cover `TimerCore` only: the renderers need a live terminal, a screen
or a device, and CI has none of those.

## Roadmap

- [x] **v0.1** core, terminal view, sound
- [x] **v0.2** `-u`: borderless always-on-top HUD with a progress ring
- [x] **v0.3** Raycast script commands
- [x] **v0.4** `-b`: BUSY Bar output over its HTTP API
- [ ] **v0.4.1** uploading your own sounds and icons to the bar
- [ ] **v0.5** Homebrew tap, universal binary, signed releases

## License

MIT
