# loopcatcher
[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)

Generic Linux audio loopback capture tool for recording app/system playback to AAC or OGG.

## Highlights
- Focused on loopback technology (PulseAudio/PipeWire monitor sink capture), not any specific platform.
- Interactive TUI for session setup, live status, and runtime config edits.
- Per-session output folders (`output_directory/session_name`) to avoid accidental overwrite.
- XDG config support at `~/.config/loopcatcher/config`.
- Debian packaging metadata and GitHub Actions workflow for release artifacts.

## Dependencies
- `pactl` (PulseAudio or PipeWire with pulse compatibility)
- `dbus-monitor`
- `parec`
- `fdkaac`
- `oggenc` (`vorbis-tools`)

## Quick start
Recommended install path (Debian/Ubuntu): download the `.deb` from GitHub Releases and install it.

1. Open releases: `https://github.com/jefonseca/loopcatcher/releases`
2. Download latest `loopcatcher_*.deb`
3. Install:
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
2. Pause playback.
3. Switch to the first track you actually want to record.
4. Start playback (the metadata refresh triggers recording correctly).

## TUI controls
- `c` open config menu
- `r` reload config from disk
- `q` quit safely (removes the loopback sink before exiting)

When playback switches to pause/stop, the session ends and the TUI waits with `Press any key to exit`.
Before stopping, capture is kept alive for ~1s so the buffered audio tail is written to the file
instead of being truncated (this can leave up to ~1s of trailing silence at the end of the last track).

On exit the virtual `nulloutput_name` sink is unloaded, so it never stays active in your audio devices list.

## Configuration
- Config path: `~/.config/loopcatcher/config`
- Override config path with `--config /path/to/config`

Main keys:
- `record_format` (`aac` or `ogg`)
- `bitrate`
- `aac_profile`
- `filename_scheme` (`normal`, `strict`, `strict-lc-nodir`)
- `output_directory`
- `sink_app_name` (app sink name to target; default keeps `spotify`)
- `nulloutput_name`
- `debug`

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
