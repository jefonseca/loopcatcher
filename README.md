[![CI](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/ci.yml)
[![Debian package](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml/badge.svg)](https://github.com/jefonseca/loopcatcher/actions/workflows/debian-package.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

# LoopCatcher

A Linux terminal app that records your media player's loopback audio
(PulseAudio/PipeWire) into organized, auto-tagged AAC or OGG files — one file
per track, no manual splitting.

LoopCatcher watches the player over MPRIS, so it knows when a track starts and
ends, and what it's called. Each track lands in its own file, named and tagged
with the artist, album, title, track number and disc number the player
reports.

- **One file per track**, split automatically — never one long recording.
- **Tagged as it records**: artist, album, album artist, title, track/disc
  number written into the file itself.
- **Organized output**: `Music/<session>/<Artist>/<Album>/<Title>.m4a`.
- **AAC (`.m4a`) or OGG (`.oga`)**, bitrate and AAC profile of your choosing.
- **Fully interactive** — a guided flow, no flags to memorize.
- **English and Spanish**, following your system locale by default.

> [!NOTE]
> The official Spotify client is what ships supported today, and you need it
> installed already — [Flathub](https://flathub.org/en/apps/com.spotify.Client)
> is the recommended way. Support for other players is a matter of writing a
> small profile — see [Profiles](#profiles).

## Requirements

On Debian 13 and recent Ubuntu everything is available from the standard
repositories. On older Debian releases you can get
[gum](https://github.com/charmbracelet/gum) from
[Charm's apt repo](https://github.com/charmbracelet/gum#installation).

```text
pactl, parec        (pulseaudio-utils)
dbus-monitor, dbus-send  (dbus)
fdkaac              (AAC output)
oggenc              (vorbis-tools, OGG output)
gum                 (the terminal UI)
```

### And the player itself

LoopCatcher records another program's audio — it does not play anything on
its own, so you also need the player the active profile targets. The profile
that ships today drives the **official Spotify desktop client**, which is
*not* installed by LoopCatcher and has to be there beforehand.

The recommended way to get it is Flathub:

**<https://flathub.org/en/apps/com.spotify.Client>**

A native `.deb` or a Snap install works too — LoopCatcher detects all three —
but Flatpak is the one we test against.

## Install

Download the latest `.deb` from
[Releases](https://github.com/jefonseca/loopcatcher/releases).

On Debian, Ubuntu and most desktops built on them, **just open the downloaded
file**: your file manager hands it to the system's package installer (GNOME
Software, Discover, GDebi…) and you install it with a click, no terminal
involved.

If your desktop has no graphical installer set up for `.deb` files, install it
from a terminal instead:

```bash
sudo apt install ./loopcatcher_*.deb
```

## Starting it

There are two ways in, and they do exactly the same thing:

- **From your application menu** — search for **Loopcatcher**. The installer
  adds the launcher, so it shows up alongside your other apps.
- **From a terminal** — run `loopcatcher`.

Either way you land on the same screen. LoopCatcher is a terminal app, so the
menu launcher just opens it in a terminal window for you.

## Quick start

Start LoopCatcher and pick **Continue**. Out of the box it drives Spotify for
you:

1. Read the requirements screen and confirm. It asks you to turn off
   Autoplay, Crossfade, Gapless and Automix in Spotify's own settings, since
   all four blur the boundary between tracks.
2. LoopCatcher launches Spotify itself, already routed into its capture sink.
3. Paste the link of the track, album or playlist you want to record.
4. It starts playback and records each track as it plays. When playback ends,
   so does the session — and Spotify is closed again.

Prefer to drive Spotify yourself? Set **Manage Spotify** to `no` under
Profile → Profile Settings, and LoopCatcher attaches to your own session
instead:

1. Open Spotify and play any track once — that creates the audio stream.
2. Pause, then select the first track you actually want to record.
3. Launch `loopcatcher` while still paused.
4. Press Play. Recording starts on its own.

Either way, `Ctrl+C` ends the session cleanly at any point: the track being
recorded is finalized rather than truncated.

## The screens

The Welcome screen shows your current configuration and the main menu:

- **Continue** — start a recording session with the active profile.
- **Profile** — Change Profile, Profile Settings (that profile's own
  options), About Profile (its README).
- **Settings** — Codecs, Paths, Enabled Profiles, Advanced, Language. Every
  field saves to disk the moment you change it; there is no Save button.
- **Apply configuration change** — appears once you've changed something.
  Relaunches the app so the change takes effect; nothing reloads while the
  app is running.
- **About** — version and license.
- **Exit** — quit, same as `Ctrl+C`.

## Configuration

Everything is editable from inside the app (Welcome → **Settings**) and saves
automatically. The file lives at `~/.config/loopcatcher/config` and can be
edited by hand too. Settings and Profile Settings changes take effect via
**Apply configuration change**, not live.

A per-session log is written to `${TMPDIR:-/tmp}/loopcatcher/<session>.log`
(or wherever `log_file_path` points), listing every captured track with its
metadata and how long it took to record. Set `log_level` to `0` to turn it
off, or `2` to add encoder diagnostics.

### Command line

```text
--help                Show help
--version             Show version
--debug               Set log_level to 2 (adds encoder diagnostics)
--logname <path>      Session log file path, for this run only
```

Everything else — output directory, session name, codec, bitrate, filename
scheme — is configured in the app.

## Profiles

Knowing how to find, watch and control a specific player lives in a loadable
**profile**, not in the main script. One ships — `spotify_native` — and it
works in either of two modes, chosen by its **Manage Spotify** setting under
Profile → Profile Settings:

| `manage_player` | How it works |
| --- | --- |
| **`yes`** *(default)* | LoopCatcher launches and controls Spotify for you. It detects a native, Flatpak or Snap install, starts it minimized and already routed into the capture sink, plays the link you paste, and closes it when the session ends. |
| **`no`** | LoopCatcher attaches to a Spotify you opened yourself. You cue the first track and press Play; LoopCatcher does the rest. |

Switch or configure the active one from Welcome → **Profile**:

- **Change Profile** — pick from the profiles listed in Settings → Enabled
  Profiles.
- **Profile Settings** — that profile's own options: **Manage Spotify**, MPRIS
  bus, sink matching, timeouts.
- **About Profile** — the profile's own README: what it captures, what it
  needs, who wrote it.

Want to capture a different player or audio source? Profiles are small,
self-contained and designed to be contributed — see
[`PROFILES.md`](PROFILES.md) for a full guide.

## Metadata and tagging

Track metadata comes from the player's MPRIS interface (title, artist, album,
album artist, track number, disc number) and is written into the output file
as it's captured. What's available depends entirely on what the player
publishes for a given track — track and disc number in particular aren't
always sent.

A track can list more than one artist. Folder and file names, and the session
log, always use the first one; file tagging differs by format, because AAC
can't represent a list:

- **OGG (`.oga`)** — every artist gets its own `ARTIST=` tag.
- **AAC (`.m4a`)** — only the first artist is tagged; MP4's artist atom holds
  a single value.

### Portable names

Folder and file names are built to survive being copied off Linux. Beyond
stripping the characters Windows and FAT/exFAT reject, each name is shortened
to at most 100 characters (cut between words, never mid-character), never
ends in a dot or a space, and is never one of the reserved Windows device
names like `CON` or `NUL`. That mainly affects the occasional enormous album
title, which would otherwise produce a folder your Linux machine accepts but
a Windows PC, a Mac or a USB stick refuses.

## Contributing

Issues and pull requests are welcome. The most useful contribution is a new
profile for a player LoopCatcher doesn't support yet —
[`PROFILES.md`](PROFILES.md) walks through the whole thing, and the shipped
profiles are small enough to read end to end.

## Disclaimer

This tool is intended for educational and operational use on audio sources you
are legally allowed to capture — royalty-free content, your own meetings, or
other permitted recordings. You are responsible for complying with local laws,
copyright rules and third-party Terms of Service. The authors are not
responsible for misuse.

## License

Released under the MIT License. See [`LICENSE`](LICENSE) for the full text.
