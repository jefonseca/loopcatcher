# LoopCatcher
[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)

A Linux TUI that captures your desktop media player's loopback audio (PulseAudio/PipeWire) into organized, auto-tagged AAC or OGG files — one file per track, no manual splitting.

## Dependencies
- [`gum`](https://github.com/charmbracelet/gum) — Debian 13+: `sudo apt install gum`; older releases: [Charm's apt repo](https://github.com/charmbracelet/gum#installation)
- `pactl` (PulseAudio, or PipeWire with pulse compatibility)
- `dbus-monitor` and `dbus-send`
- `parec`
- `fdkaac` (for AAC) and/or `oggenc` (`vorbis-tools`, for OGG)

## Install
Download the latest `.deb` from [Releases](https://github.com/jefonseca/loopcatcher/releases) and install it:
```bash
sudo apt install ./loopcatcher_*.deb
```
Or run it straight from source:
```bash
chmod +x loopcatcher
./loopcatcher
```

## Usage
Just run `loopcatcher` and follow the screens — it's fully interactive (needs a terminal, no scripted/headless mode). If you installed the `.deb` package, a "Loopcatcher" launcher is also available from your desktop's application menu.

Recommended flow for a clean first track:
1. Open your player and play any track once (creates the sink).
2. Pause, then select the first track you actually want to record.
3. Launch `loopcatcher` while still paused.
4. Press Play — recording starts automatically.

Runtime overrides:
```bash
./loopcatcher --output /path/to/output --session my-session
```

## CLI options
```text
--help                    Show help
--version                 Show version
--debug                   Set log_level to 2 (adds encoder diagnostics to the session log)
--output <dir>            Output directory
--session <name>          Session name (skips the prompt)
--format <format>         Record format: aac or ogg
--aac-profile <id>        AAC profile (aac only)
--bitrate <kbps>          Bitrate target (default 48; raise it if using ogg)
--scheme <scheme>         Filename scheme: normal, strict, strict-lc-nodir
--config <path>           Config file path override
```

## Configuration
Everything is editable from the app itself (Welcome → **Change configuration**) and saves automatically as you change it — no separate Save step. The file lives at `~/.config/loopcatcher/config` and can also be edited directly; `--config <path>` points at a different one.

A per-session log is written under `${TMPDIR:-/tmp}/loopcatcher/` (or `log_directory`, if set) listing every captured track with its metadata and how long it took to record. Set `log_level` to `0` to disable it, or `2` to add encoder diagnostics.

## Metadata
Track metadata comes from the player's MPRIS interface (title, artist, album, album artist, track number, disc number) and is written into the output file as it's captured. Availability depends entirely on what the player publishes for a given track — track/disc number in particular aren't always sent.

`xesam:artist` can hold more than one name. Where the artist appears elsewhere, only the first name is used — output folder/file names and the session log always do this, regardless of format — but file tagging differs by format because AAC can't represent it losslessly:
- **OGG (`.oga`)**: every artist gets its own `ARTIST=` tag.
- **AAC (`.m4a`)**: only the first artist is tagged — MP4's artist atom holds a single value, not a list.

## Disclaimer
This tool is intended for educational and operational use on audio sources you are legally allowed to capture (for example, royalty-free content, your own meetings, or other permitted recordings). You are responsible for complying with local laws, copyright rules, and third-party Terms of Service. The authors are not responsible for misuse.

## License
Released under the MIT License. See [`LICENSE`](LICENSE) for the full text.
