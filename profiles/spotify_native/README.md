# Spotify official player

Captures loopback audio from the official Spotify client for Linux via its
MPRIS interface (`org.mpris.MediaPlayer2.spotify` by default).

- **Author:** Kike Fonseca
- **License:** MIT (same as loopcatcher itself)
- **Detection:** matches a PulseAudio/PipeWire sink-input by application name
  (`Sink App Name` / `Sink Match`, space-separated glob patterns) and reads
  track metadata (title, artist, album, album artist, track number, disc
  number) from Spotify's MPRIS bus (`MPRIS Bus`).
- **Requires:** `dbus-monitor` and `dbus-send` (part of the `dbus` package),
  plus `pactl` and `parec` (part of `pulseaudio-utils`).

Adjust its settings from the app's **Profile → Profile Settings** screen;
they are saved automatically as soon as you change them, just like every
other setting in loopcatcher.
