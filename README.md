# LoopCatcher
[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)

Generic Linux audio loopback capture tool for recording app/system playback to AAC or OGG.

## Highlights
- Focused on loopback technology (PulseAudio/PipeWire monitor sink capture), not any specific platform.
- Interactive TUI for session setup, live status, and runtime config edits.
- Per-session output folders (`output_directory/session_name`) to avoid accidental overwrite.
- XDG config support at `~/.config/loopcatcher/config`.

## Dependencies
- `pactl` (PulseAudio or PipeWire with pulse compatibility)
- `dbus-monitor`
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

Recommended playback flow:
1. Open your player software and play any track once (this creates the sink-input).
2. Pause, then select the first track you actually want to record.
3. Launch loopcatcher while playback is still paused.
4. Press Play — the metadata refresh triggers recording.

Recording starts roughly 100–150 ms after Play and each track goes to its own file.
Track-to-track handoff is near gapless (the previous file is finalized in the background).
Capture runs at low latency (`parec --latency-msec=30`) so both ends track playback closely.

## TUI controls
- `c` open config menu
- `r` reload config from disk
- `q` quit safely (finalizes the current file and removes the loopback sink)

The dashboard runs on the terminal's alternate screen (your scrollback is untouched and
restored on exit) and shows an animated indicator while recording.

Once playback has started, **any** non-`Playing` state (pause or stop) ends the session —
no half tracks, and this is the state Spotify lands in when a playlist finishes. A pause
*before* the first Play (during setup) is ignored so it can't abort prematurely.
When the session ends the TUI waits with `Press any key to exit`.

Before stopping, capture is kept running for `tail_drain_seconds` (default `0.35`, configurable)
so the buffered audio tail lands in the file instead of being cut. The trade-off is up to that
much near-silence at the very end of the last track; set it to `0` to disable.

On exit the virtual `nulloutput_name` sink is unloaded, so it never stays active in your audio devices list.

## Configuration
- Config path: `~/.config/loopcatcher/config`
- Override config path with `--config /path/to/config`

Main keys:
- `record_format` (`aac` or `ogg`)
- `bitrate` (kbps; default `48`)
- `aac_profile`
- `filename_scheme` (`normal`, `strict`, `strict-lc-nodir`) — `normal` keeps Unicode
  letters (accents, non-Latin scripts) and only strips path-unsafe / FAT/NTFS-reserved
  characters; `strict*` reduce names to ASCII alphanumerics.
- `output_directory`
- `sink_app_name` (app sink name to target; default keeps `spotify`)
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
--no-intro                Skip startup intro screen
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
