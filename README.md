# LoopCatcher
[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)

Generic Linux audio loopback capture tool for recording app/system playback to AAC or OGG.

## Highlights
- Focused on loopback technology (PulseAudio/PipeWire monitor sink capture), not any specific platform.
- [`gum`](https://github.com/charmbracelet/gum)-based TUI: one-time onboarding wizard, guided no-sink setup, live status view, runtime config menu.
- Player profiles scope the MPRIS monitor to the selected player, so other media players never trigger a recording.
- Per-session output folders (`output_directory/session_name`) to avoid accidental overwrite.
- XDG config support at `~/.config/loopcatcher/config`.

## Dependencies
- `gum` (`charmbracelet/gum`) — in Debian 13 `main` (`sudo apt install gum`); on older
  distros add the [Charm apt repo](https://github.com/charmbracelet/gum#installation)
- `pactl` (PulseAudio or PipeWire with pulse compatibility)
- `dbus-monitor` and `dbus-send`
- `parec`
- `fdkaac`
- `oggenc` (`vorbis-tools`)

## Quick start
Recommended install path (Debian/Ubuntu): download the `.deb` from GitHub Releases and install it.

1. Open [Releases](https://github.com/jefonseca/loopcatcher/releases)
2. Download latest `loopcatcher_*.deb`
3. Install it one of two ways:
   - **Graphical (Debian):** double-click the downloaded `.deb`. It opens in your
     OS software store (GNOME Software or Plasma Discover) — click **Install**.
   - **Terminal:**
     ```bash
     sudo apt install ./loopcatcher_*.deb
     ```

Then run:
```bash
loopcatcher
```

Alternative (run from source):
```bash
chmod +x loopcatcher
./loopcatcher
```

You can provide runtime overrides:
```bash
./loopcatcher --output /path/to/output --session my-session
```

First run only: a one-time `gum` onboarding wizard asks for the player profile, codec,
bitrate, filename scheme and output directory, then writes
`~/.config/loopcatcher/config`. It never reappears once that file exists (delete it to
run the wizard again).

Then it goes straight to session setup. The **session name** prompt suggests a
timestamped name (`<date>-<time>-loopcatcher`) as its placeholder, so you can just press
Enter to accept it. Pass `--session <name>` to skip the prompt entirely.

Recommended playback flow:
1. Open your player software and play any track once (this creates the sink-input).
2. Pause, then select the first track you actually want to record.
3. Launch loopcatcher while playback is still paused.
4. Press Play — the metadata refresh triggers recording.

If loopcatcher can't find the player sink at launch it drops into a guided wizard that
polls for it and walks you through the play/pause setup before continuing.

Recording starts roughly 100–150 ms after Play and each track goes to its own file.
Track-to-track handoff is near gapless (the previous file is finalized in the background).
Capture runs at low latency (`parec --latency-msec=30`) so both ends track playback closely.

## The menu
In the live status view, press **`m`** to open a `gum` filter menu (type to narrow the
list):
- **Resume** — back to the status view
- **Config** — the configuration menu (grouped: Codecs, Paths, Player, Advanced)
- **Reload config** — re-read the config file from disk
- **About** — installed-package metadata, or a run-from-source fallback
- **License**
- **Quit** — finalizes the current file and removes the loopback sink

The live status view runs on the terminal's alternate screen (your scrollback is
untouched and restored on exit) and shows an animated indicator while recording.

Once playback has started, **any** non-`Playing` state (pause or stop) ends the session —
no half tracks, and this is the state Spotify lands in when a playlist finishes. A pause
*before* the first Play (during setup) is ignored so it can't abort prematurely.
When the session ends, loopcatcher prints *Recording finished, exiting...* and exits
automatically (the last file path stays in your scrollback).

Before stopping, capture is kept running for `tail_drain_seconds` (default `0.35`, configurable)
so the buffered audio tail lands in the file instead of being cut. The trade-off is up to that
much near-silence at the very end of the last track; set it to `0` to disable.

On exit the virtual `nulloutput_name` sink is unloaded, so it never stays active in your audio devices list.

## Configuration
- Config path: `~/.config/loopcatcher/config`
- Override config path with `--config /path/to/config`

Main keys:
- `player_profile` — `spotify` or `custom`.
  - `spotify` fills the three detection fields below with Spotify's values.
  - `custom` lets you edit them by hand (they are prefilled with the current values).
  All four are persisted to the config file.
- `sink_app_name` — app name to match in the audio sink-input.
- `player_mpris_bus` — MPRIS bus name; scopes the D-Bus monitor to that player
  (`org.mpris.MediaPlayer2.<player>`), so other MPRIS players never trigger a recording.
- `player_sink_match` — space-separated globs matched (case-insensitively) against the
  sink-input `application.name`.
- `record_format` (`aac` or `ogg`)
- `bitrate` (kbps; default `48`)
- `aac_profile` — applies to `aac` only.
- `filename_scheme` (`normal`, `strict`, `strict-lc-nodir`) — `normal` keeps Unicode
  letters (accents, non-Latin scripts) and only strips path-unsafe / FAT/NTFS-reserved
  characters; `strict*` reduce names to ASCII alphanumerics.
- `output_directory`
- `nulloutput_name`
- `tail_drain_seconds` (extra capture time after playback stops; `0` disables)
- `debug`

> **Note:** the default `bitrate` of `48` is tuned for AAC (HE-AAC v2). OGG/Vorbis
> sounds poor at that rate — if you set `record_format=ogg`, raise `bitrate` in the
> config (e.g. `128` or higher) as well.

Only one artist is used for tagging and the folder tree (multi-artist tracks would
otherwise explode into a huge folder/file structure).

## CLI options
```text
--help                    Show help
--version                 Show version
--debug                   Enable debug
--output <dir>            Output directory
--session <name>          Session name override
--format <format>         Record format: aac or ogg
--aac-profile <id>        AAC profile (aac only)
--bitrate <kbps>          Bitrate target
--scheme <scheme>         Filename scheme
--config <path>           Config path override
--no-intro                Skip the first-run onboarding wizard (writes defaults)
```

Validation notes:
- `--format` only accepts `aac` or `ogg`
- `--scheme` only accepts `normal`, `strict`, `strict-lc-nodir`
- `--bitrate` and `--aac-profile` must be positive integers

## Build .deb package
```bash
dpkg-buildpackage -us -uc -b
```

For most users, prefer the prebuilt package from Releases instead of building locally.

## Quality checks
Local checks:
```bash
bash -n loopcatcher
shellcheck loopcatcher tests/test.sh
./tests/test.sh
```

CI runs on push/PR for syntax, ShellCheck, and tests. Release/tag pipeline also runs preflight checks before building `.deb` artifacts.

## Disclaimer
This tool is intended for educational and operational use on audio sources you are legally allowed to capture (for example, royalty-free content, your own meetings, or other permitted recordings). You are responsible for complying with local laws, copyright rules, and third-party Terms of Service. The authors are not responsible for misuse.

## License
Released under the MIT License. See [`LICENSE`](LICENSE) for the full text.
