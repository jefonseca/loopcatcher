# Spotify official player (managed)

Launches and fully controls the official Spotify client for Linux via its
MPRIS interface (`org.mpris.MediaPlayer2.spotify` by default). Unlike
`spotify_native`, this profile starts Spotify itself - with the capture sink
already selected via `PULSE_SINK`, so no sink move is needed - asks you for
a Spotify track/album/playlist link, plays it via MPRIS `OpenUri`, and
closes Spotify again once the recording session ends.

- **Author:** Kike Fonseca
- **License:** MIT (same as loopcatcher itself)
- **Default profile:** this is the profile a fresh loopcatcher install starts
  on. Switch to another one any time from **Profile → Change Profile**.
- **Detection/launch:** checks, in order, for a native `spotify` binary, a
  Flatpak install (`com.spotify.Client`), and a Snap install (`spotify`) -
  the first one found launches Spotify with `PULSE_SINK` already pointed at
  loopcatcher's capture sink. Playback is driven entirely via MPRIS; the bus
  (`MPRIS Bus`) is polled after launch, up to `MPRIS Wait Timeout` seconds,
  to confirm Spotify actually started.
- **Requires:** `dbus-monitor`/`dbus-send` (`dbus`), `pactl`/`parec`
  (`pulseaudio-utils`), and one of: `spotify` on `PATH`, `flatpak` with
  `com.spotify.Client` installed, or `snap` with `spotify` installed.
- **Before you start:** close any already-running Spotify instance, and
  disable Autoplay, Crossfade songs, Gapless playback, and Automix in
  Spotify's own settings - the in-app Requirements screen walks through
  this before anything is launched.

Adjust its settings from the app's **Profile → Profile Settings** screen;
they are saved automatically as soon as you change them, just like every
other setting in loopcatcher.
