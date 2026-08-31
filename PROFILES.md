# Writing a LoopCatcher profile

LoopCatcher itself doesn't know anything about Spotify, VLC, Firefox, or any
other program. All of that knowledge — how to find the player's audio, how
to tell when a track starts, where to read the title and artist from — lives
in a small, self-contained **profile**. The main script only knows how to
load a profile, ask it to do its thing, and record whatever audio the
profile routes its way.

This document is a guide for writing your own. If you'd rather learn by
reading real code, `profiles/spotify_native/` is the one profile that ships
today, and every example below is drawn from it.

## What a profile actually is

A profile is a folder under `profiles/` whose name becomes the profile's own
identifier — it's what shows up as `default_profile` in the config file, and
it's the prefix every one of the profile's own settings gets. Pick something
short, lowercase, and specific: `spotify_native`, not `spotify` (there could
one day be more than one way to capture Spotify) or `player` (too vague).

```
profiles/
  your_profile_name/
    profile.sh       # required — the code
    lang/
      en.sh           # required — your strings, in English
      es.sh           # optional — your strings, in Spanish
    README.md         # required — shown to users as "About Profile"
```

That's it. Drop a folder shaped like this under `profiles/` and LoopCatcher
will discover it automatically — nothing else to register anywhere. A user
still has to enable it (Settings → Enabled Profiles) and pick it as their
default (Profile → Change Profile) before it actually runs, but the app sees
it the moment the folder exists.

`profile.sh` is not a standalone script. LoopCatcher `source`s it straight
into its own process, the same way you'd `source` a shell library — it's
never executed on its own, and it never gets its own `#!/bin/bash`
interpreter invocation. That means your profile shares the main script's
whole toolbox: every generic helper it defines (drawing the screen, routing
audio, writing files, translating strings) is just a function call away.
It also means only **one** profile is ever loaded into memory at a time, so
you don't need to worry about naming collisions with some other profile's
internal function names — just with LoopCatcher's own (see the reference
list further down).

## The seven functions LoopCatcher expects from you

This is the whole contract. Define these seven functions and your profile
is a profile.

### `profile_label()`

Print your profile's friendly name — what shows up in menus and headings.

```bash
profile_label () {
    t your_profile_name.label
}
```

### `profile_config_schema()`

Describe the settings your profile wants to expose, one per line, tab-
separated:

```
key<TAB>label<TAB>default<TAB>kind[<TAB>choices]
```

- **key** must be prefixed with your profile's name, e.g.
  `your_profile_name_some_setting`. This is what actually gets written to
  the config file.
- **label** is what the user sees on the Profile Settings screen. Route it
  through `t()` so it's translatable (see "Strings and translations" below).
- **default** is the value used the very first time your profile is
  selected — more on this in a moment.
- **kind** is either `input` (free text, via `gum input`) or `choice` (a
  fixed set of options, via `gum choose`).
- **choices** is only needed for `kind=choice`: a space-separated list of
  the allowed values.

```bash
profile_config_schema () {
    printf 'your_profile_name_sink_app_name\t%s\tvlc\tinput\n' \
        "$(t your_profile_name.field.sink_app_name)"
}
```

This does double duty: it's what draws the Profile Settings screen, *and*
it's how LoopCatcher knows which config keys belong to you when it saves the
file.

### `profile_apply_defaults()`

Set your prefixed settings to their real default values (matching whatever
you wrote in the schema above), then call `profile_activate` (next section)
so the rest of the app can actually use them right away.

```bash
profile_apply_defaults () {
    your_profile_name_sink_app_name="vlc"
    profile_activate
}
```

This runs exactly once per profile: the first time a user ever selects it.
LoopCatcher checks whether any of your schema's keys already exist in the
saved config — if none do, it calls this function and immediately writes
the result to disk, so from then on your profile's settings are just sitting
in the config file like everyone else's.

**One important rule:** don't give your variables a fallback default at the
top of `profile.sh` (no `your_profile_name_sink_app_name="${your_profile_name_sink_app_name:-vlc}"`
tricks). That's exactly the check described above — if the variable always
has *some* value the moment your file is sourced, LoopCatcher can never tell
whether this is truly the first run, and `profile_apply_defaults` never
gets called. Leave your settings genuinely undeclared until either the saved
config or `profile_apply_defaults` sets them.

### `profile_activate()`

Copy your own prefixed settings into the handful of generic variables the
rest of LoopCatcher already knows how to use for finding and routing audio:
`sink_app_name` and `player_sink_match`.

```bash
profile_activate () {
    sink_app_name="$your_profile_name_sink_app_name"
    player_sink_match="$your_profile_name_sink_match"
}
```

Why the indirection? So that LoopCatcher's sink-matching code never has to
know your profile's name or prefix — it just reads `sink_app_name`, no
matter which profile put it there. This runs once, right after your
settings are loaded from disk.

Feel free to alias more of your own settings into plain, unprefixed
variables here too, if it's convenient for the rest of your code — LoopCatcher
only reads `sink_app_name`/`player_sink_match` itself, but nothing stops you
from doing the same thing for your own internal use. `spotify_native` does
exactly this with `player_mpris_bus`, which nothing outside that one profile
ever touches.

### `profile_wait_condition(kind)`

The Recording Wizard walks the user through up to three steps before a
session actually starts, and the very last one is always "wait until
something happens, then move on" — LoopCatcher handles the *first* step
itself (waiting for the audio sink to appear, since every profile needs
one), but the rest are yours to define. `profile_wait_condition` is how you
tell it when a named condition is true:

```bash
profile_wait_condition () {
    case "$1" in
        paused)  your_player_is_paused ;;
        playing) your_player_is_playing ;;
        *)       return 1 ;;
    esac
}
```

The names you use for `kind` (here `paused`/`playing`) are entirely up to
you — they're just the strings you'll pass to `wizard_step_screen` in
`profile_run` below.

### `profile_run()`

The big one: this is your whole session, start to finish. It's called once
Session Name has already been picked, and it doesn't return until the
recording session is over. Broadly, it needs to:

1. Wait for the player's audio sink to show up (`get_target_sink_index`).
2. Route that sink into LoopCatcher's own capture sink, **as early as
   possible** — right after step 1, not right before recording starts. If
   you route it late, the first moments of the very first track play out
   the user's real speakers instead of being captured.
3. Walk through whatever wizard steps your player needs (pause, then play —
   or whatever makes sense for your source), using `wizard_step_screen` and
   your own `profile_wait_condition` kinds.
4. Start whatever background monitoring you need (a coprocess, a polling
   loop, a socket — whatever fits your player) to notice track changes.
5. Hand control to the Recording screen: draw it, then loop until the
   session ends, calling `start_recording`/`stop_current_recording` as
   tracks come and go.

```bash
profile_run () {
    local label
    label="$(profile_label)"

    if ! get_target_sink_index; then
        wizard_step_screen 1 points sink "$(t your_profile_name.wizard.step1_heading)" \
            "$(t your_profile_name.wizard.step1_line1 "$label")"
        get_target_sink_index || true
    fi

    create_null_audio_output
    move_target_output

    if ! your_player_is_paused; then
        wizard_step_screen 2 points paused "$(t your_profile_name.wizard.step2_heading)" \
            "$(t your_profile_name.wizard.step2_line1 "$label")"
    fi

    start_your_monitor   # however your profile notices track changes

    if ! your_player_is_playing; then
        wizard_step_screen 3 points playing "$(t your_profile_name.wizard.step3_heading)" \
            "$(t your_profile_name.wizard.step3_line1)"
    fi

    screen_enter
    your_recording_main_loop   # draws the Recording screen and reacts to events
}
```

`profiles/spotify_native/profile.sh`'s own `profile_run` is a complete,
working version of this — read it alongside this section if anything above
is unclear. Its comments call out the two ordering rules that actually
matter (routing the sink early, and exactly when to start its monitor) in
more detail than fits here.

### `profile_cleanup()`

Whatever you started in `profile_run` that needs to be stopped when
LoopCatcher exits — a background process, an open connection — stop it
here. This runs no matter how the session ends: normally, via Ctrl+C, or
because something crashed.

```bash
profile_cleanup () {
    if [[ -n "$your_monitor_pid" ]] && kill -0 "$your_monitor_pid" 2>/dev/null; then
        kill "$your_monitor_pid" 2>/dev/null || true
    fi
}
```

## What LoopCatcher gives you to build with

Your profile doesn't have to build a TUI from scratch or reimplement audio
routing. All of the following are already there, ready to call:

| Function | What it does |
| --- | --- |
| `get_target_sink_index` | Finds the sink-input matching `sink_app_name`/`player_sink_match`, sets `source_sink_index` |
| `ensure_target_routed` | Re-routes the cached (or freshly re-detected) sink-input into LoopCatcher's capture sink |
| `create_null_audio_output` | Creates LoopCatcher's own capture sink (idempotent — safe to call every session) |
| `move_target_output` | Moves `source_sink_index` into that capture sink |
| `wizard_step_screen n spinner kind heading line...` | Draws one numbered Recording Wizard step and waits for `kind` to become true |
| `start_recording artist album title albumartist tracknumber discnumber` | Starts encoding a new track; returns non-zero if it couldn't |
| `stop_current_recording [quick\|drain]` | Stops the current recording (`quick` for a track change, `drain` when the session is ending) |
| `end_session` | Marks the session over — LoopCatcher will show the Finish screen next |
| `tui_set field value` | Updates one field (`track`/`artist`/`album`/`tracknumber`/`discnumber`/`output`) on the Recording screen |
| `status_output_relpath` | The current output file's path, relative to the session folder — handy for display |
| `screen_enter` / `screen_leave` | Switches the terminal in and out of the alternate screen buffer |
| `paint_frame text` | Repaints the Recording screen in place, without a full clear |
| `ui_kv_table col1 col2 label val ...` | Draws one of the bordered "Field / Value" tables |
| `clip_text value [max]` | Shortens a long value so a table row doesn't wrap |
| `log_line` / `log_debug` / `log_recording` | Writes to the session log, gated by the user's Log Level setting |
| `t message.id [args...]` | Looks up a translated string (see next section) |

You'll also find a handful of read-only variables already populated for
you when `profile_run` starts: `output_directory`, `session_name`,
`session_output_directory`, `config_path`, `nulloutput_name`, and
`artist_all` (an array — leave it empty if your player only ever reports one
artist per track; LoopCatcher's tagging code already handles that case).

## Strings and translations

Every piece of text your profile shows on screen should go through `t()`
rather than being written as a plain string — that's what makes it
translatable, and it's what the rest of the app does everywhere too.

Your `lang/en.sh` is where those strings live. It's plain data — a handful
of assignments into an array LoopCatcher already created, no functions, no
logic:

```bash
# shellcheck shell=bash
MSG_en[your_profile_name.label]='Your Player'
MSG_en[your_profile_name.field.sink_app_name]='Sink App Name'
MSG_en[your_profile_name.wizard.step1_heading]='Create the Audio Sink'
MSG_en[your_profile_name.wizard.step1_line1]='1) Open your %s'
```

A few rules worth knowing:

- **English is the fallback.** If a translation is missing an id, LoopCatcher
  falls back to whatever `lang/en.sh` has for it — so `lang/en.sh` has to be
  complete (every id you ever call `t` with needs an entry there), but
  `lang/es.sh` and any other language don't. Add translations at your own
  pace; nothing breaks in the meantime.
- **`%s` placeholders** work exactly like `printf` — `t your_profile_name.wizard.step1_line1 "$label"`
  fills in `%s` with `$label`. Keep the same number of `%s` placeholders,
  in the same order, across every language's version of the same id.
- **Namespace your ids** with your profile's name (`your_profile_name.*`),
  the same way your config keys are prefixed — it keeps everything findable
  and avoids collisions with the main app's own ids or another profile's.
- Prefer full sentences over fragments, and write them the way you'd
  actually say them — not literal word-for-word translations.

## Your README: the "About Profile" screen

`profiles/your_profile_name/README.md` is shown verbatim, exactly as you
write it, when someone picks **About Profile** from the Profile menu. It's
never translated and never parsed — it's just your own note to the user, in
whatever format you like (though plain Markdown-flavored text reads best in
a terminal pager). A good one answers:

- What does this profile capture, and how does it find it?
- Who wrote it, and under what license?
- Does it need anything beyond LoopCatcher's own dependencies?

`profiles/spotify_native/README.md` is a short, complete example.

## Enabling and selecting your profile

Dropping a folder under `profiles/` makes LoopCatcher aware of it, but two
more steps make it actually usable:

1. **Settings → Enabled Profiles** — add your profile to the list. A profile
   that isn't enabled can't be selected, even if someone tries.
2. **Profile → Change Profile** — pick it as the active one.

Both of these save immediately but, like every other setting, only take
effect after **Apply configuration change** on the Welcome menu.

## Testing your profile

Before you open a pull request:

```bash
bash -n profiles/your_profile_name/profile.sh
bash -n profiles/your_profile_name/lang/en.sh
shellcheck -e SC1090,SC2030,SC2031,SC2034,SC2154,SC2317 profiles/your_profile_name/profile.sh profiles/your_profile_name/lang/*.sh
```

The exclude list on that `shellcheck` command isn't you being let off easy —
it's silencing warnings that are simply wrong for a file that's designed to
be `source`d into another script's namespace (ShellCheck can't see that
`sink_app_name` or `t` are defined elsewhere, for instance). Everything else
it flags is worth fixing.

`./tests/test.sh` runs the whole project's test suite and should still pass
unmodified — it doesn't know about your profile yet, and it doesn't need to
for your PR to be useful. If you want to add tests of your own alongside
it, look at how the existing tests stub out `gum`/`dbus-monitor`/etc. in
`tests/test.sh` for the pattern to follow.

Beyond the automated checks, actually run it: enable your profile, select
it, and walk through a real session against the player or source you're
targeting. There's no substitute for watching it capture a real track.

## Checklist

- [ ] `profiles/your_profile_name/profile.sh` defines all seven hook
      functions
- [ ] No config variable is self-defaulted at the top of `profile.sh`
- [ ] `profiles/your_profile_name/lang/en.sh` has an entry for every id you
      call `t` with
- [ ] `profiles/your_profile_name/README.md` explains what it captures, how,
      and by whom
- [ ] `bash -n` and `shellcheck` are clean
- [ ] You've actually recorded something real with it

Questions or stuck somewhere? Open an issue — and if you get your profile
working, we'd love to see it as a pull request.
