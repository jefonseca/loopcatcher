[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)

# LoopCatcher
A Linux TUI that captures your desktop media player's loopback audio (PulseAudio/PipeWire) into organized, auto-tagged AAC or OGG files — one file per track, no manual splitting.

> [!NOTE]
> - The Spotify Official client is supported

## Installing

### Dependencies

On Debian/GNU Linux 13 you will have all the necesary, on recent versions of Ubuntu too.
On older Debian releases cant use [Charm's apt repo](https://github.com/charmbracelet/gum#installation) to install [gum](https://github.com/charmbracelet/gum)

> [!NOTE]
> Specific dependencies:
> 
>`pactl, dbus-monitor, dbus-send, parec, fdkaac, oggenc (vorbis-tools), gum`

### Install
Download the latest `.deb` from [Releases](https://github.com/jefonseca/loopcatcher/releases) and install it:
```bash
sudo apt install ./loopcatcher_*.deb
```

## Usage
Just run `loopcatcher` and follow the screens — it's fully interactive (needs a terminal, no scripted/headless mode). If you installed the `.deb` package, a "Loopcatcher" launcher is also available from your desktop's application menu.

The Welcome screen shows your current configuration and a main menu:
- **Continue** — start a recording session with the active profile.
- **Profile** — Change Profile (pick which player module is active), Profile
  Settings (that module's own options), About Profile (its README).
- **Settings** — Codecs, Paths, Enabled Profiles, Advanced, Language. Every
  field saves to disk automatically as you change it — no separate Save step.
- **Apply configuration change** — only shown once you've actually changed
  something; relaunches the app so it takes effect (nothing reloads while
  the app keeps running).
- **About** — app version and license.
- **Exit** — quit (same as Ctrl+C anywhere else in the app).

Recommended flow for a clean first track:
1. Open your player and play any track once (creates the sink).
2. Pause, then select the first track you actually want to record.
3. Launch `loopcatcher` while still paused.
4. Press Play — recording starts automatically.

Available in English and Spanish. Settings → Language defaults to **auto** (follows your system locale, live — not just on first run) and can be pinned to `en` or `es`; pick **auto** again any time to go back to following the system locale. Pick Apply configuration change afterward.

## CLI options
```text
--help                    Show help
--version                 Show version
--debug                   Set log_level to 2 (adds encoder diagnostics to the session log)
--logname <path>          Session log file path (overrides log_file_path for this run)
```
Everything else (output directory, session name, codec, bitrate, filename scheme, ...) is config/TUI-only now — see Configuration below.

## Configuration
Everything is editable from the app itself (Welcome → **Settings**) and saves automatically as you change it — no separate Save step. The file lives at `~/.config/loopcatcher/config` and can also be edited directly. Settings/Profile Settings changes apply via **Apply configuration change** on the Welcome menu, not live.

A per-session log is written to `${TMPDIR:-/tmp}/loopcatcher/<session-name>.log` (or `log_file_path`, if set) listing every captured track with its metadata and how long it took to record. Set `log_level` to `0` to disable it, or `2` to add encoder diagnostics.

## Profiles
Detecting and monitoring a specific player lives in a loadable **profile module**, not the main script — today only `spotify_native` ships, but the app is built to support more. Switch or configure the active one from Welcome → **Profile**:
- **Change Profile** — pick the default profile from the ones listed in Settings → Enabled Profiles.
- **Profile Settings** — that module's own options (e.g. spotify_native's Sink App Name / MPRIS Bus / Sink Match).
- **About Profile** — the module's own README (author, license, requirements).

Want to capture a different player or audio source? See
[`PROFILES.md`](PROFILES.md) for how to write and contribute a new profile.

## Metadata
Track metadata comes from the player's MPRIS interface (title, artist, album, album artist, track number, disc number) and is written into the output file as it's captured. Availability depends entirely on what the player publishes for a given track — track/disc number in particular aren't always sent.

`xesam:artist` can hold more than one name. Where the artist appears elsewhere, only the first name is used — output folder/file names and the session log always do this, regardless of format — but file tagging differs by format because AAC can't represent it losslessly:
- **OGG (`.oga`)**: every artist gets its own `ARTIST=` tag.
- **AAC (`.m4a`)**: only the first artist is tagged — MP4's artist atom holds a single value, not a list.

## Disclaimer
This tool is intended for educational and operational use on audio sources you are legally allowed to capture (for example, royalty-free content, your own meetings, or other permitted recordings). You are responsible for complying with local laws, copyright rules, and third-party Terms of Service. The authors are not responsible for misuse.

## License
Released under the MIT License. See [`LICENSE`](LICENSE) for the full text.
