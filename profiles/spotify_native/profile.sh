#!/usr/bin/env bash
###############################################################################
# spotify_native profile module for loopcatcher.
#
# Like spotify_native, detects and captures the official Spotify Linux
# client via its MPRIS interface - but instead of attaching to an instance
# the user already opened/paused/routed by hand, this module takes control:
# it detects how Spotify is installed (native/Flatpak/Snap), launches it
# itself with PULSE_SINK already pointed at the capture sink (so no sink
# move is needed), asks for a track/album/playlist URL, starts playback
# itself via MPRIS OpenUri, and closes the Spotify process it launched once
# the session ends. This file is `source`d directly into the main script's
# process by load_profile_module() - never executed on its own - so it
# shares the main script's global namespace and can call any of its generic
# helpers (get_target_sink_index, create_null_audio_output, screen_enter/
# screen_leave, start_recording, stop_current_recording, end_session,
# tui_set, log_line/log_debug, ui_kv_table,
# paint_frame, render_page, ui_box, ui_notify, ui_gap, ...).
#
# This module deliberately copies (rather than shares) spotify_native's
# MPRIS/recording-loop machinery - every profile module is meant to be
# fully self-contained (see AGENTS.md's "Profile modules" section), so
# deleting this directory removes 100% of what it owns.
#
# Every profile module must define this hook contract (see AGENTS.md):
#   profile_label()            friendly display name
#   profile_config_schema()    "key\tlabel\tdefault\tkind[\tchoices]" rows
#   profile_apply_defaults()   reset this module's settings to their defaults
#   profile_activate()         alias persisted settings into runtime vars
#   profile_wait_condition(k)  true once wizard-step condition "k" holds
#   profile_run()               the whole per-session flow (wizard -> finish)
#   profile_cleanup()          kill/tear down anything this module started
###############################################################################

readonly SPOTIFY_NATIVE_MPRIS_BUS="org.mpris.MediaPlayer2.spotify"
readonly SPOTIFY_NATIVE_SINK_MATCH="spotify spotify* com.spotify.client com.spotify.client* com.spotify.Client*"
readonly SPOTIFY_NATIVE_FLATPAK_APP_ID="com.spotify.Client"
readonly SPOTIFY_NATIVE_SNAP_NAME="spotify"
# https://open.spotify.com/track/<id>, .../album/<id>, .../playlist/<id> -
# optionally prefixed with a locale segment (e.g. "intl-es/"), optionally
# suffixed with a "?si=..." query string. Captures: (1) type (2) id.
readonly SPOTIFY_NATIVE_URL_RE='^https?://open\.spotify\.com/(intl-[a-zA-Z-]+/)?(track|album|playlist)/([A-Za-z0-9]{22})(\?.*)?$'

# --- persisted to the config file, prefixed spotify_native_* ---
# Deliberately NOT self-defaulted here (e.g. via "${var:-default}"): load_config
# checks whether these are already set - by the config file it just sourced -
# to decide whether this module needs seeding via profile_apply_defaults(). A
# self-default here would make that check always true and defeat it.

# --- MPRIS monitor / recording-loop state (not persisted) - same shape as
# spotify_native's own equivalent block ---
dbus_monitor_pid=""
playbackstatus="Unknown"
started_playing=false
player_missing_polls=0    # consecutive liveness polls with the player bus gone
active_recording_signature=""
trackid=""
last_trackid=""
title=""
artist=""       # first xesam:artist value - used for naming, log, AAC tag
# artist_all (every xesam:artist value) is declared generically by the main
# script, not here - see loopcatcher's Global State section.
album=""
albumartist=""
tracknumber=""
discnumber=""

# --- this module's own state: which Spotify install was launched, and how
# to tear it back down in profile_cleanup() (not persisted) ---
managed_install_type=""   # "native" | "flatpak" | "snap"
managed_pid=""            # native only - the backgrounded launch command's $!
managed_spotify_uri=""    # e.g. "spotify:album:0eRXMxgNfJ33uykapOFtZp"
# Only true once launch_spotify() has actually started a process. Gates the
# teardown in profile_cleanup(), which must never close a Spotify this module
# did not open - notably on the "Spotify is already running, close it and try
# again" exit path, where the install type IS known but the running instance
# is the user's own.
managed_launched=false

###############################################################################
# Module hook contract
###############################################################################

profile_label () {
    t spotify_native.label
}

# One row per config field: key<TAB>label<TAB>default<TAB>kind[<TAB>choices]
# "kind" is "input" or "choice" (choices space-separated in the 5th field) -
# drives both the generic Profile Settings editor and config-seeding. Labels
# come from this module's own lang/ files (t spotify_native.field.*).
profile_config_schema () {
    printf 'spotify_native_manage_player\t%s\tyes\tchoice\tyes no\n' "$(t spotify_native.field.manage_player)"
    printf 'spotify_native_sink_app_name\t%s\tspotify\tinput\n' "$(t spotify_native.field.sink_app_name)"
    printf 'spotify_native_mpris_bus\t%s\t%s\tinput\n' "$(t spotify_native.field.mpris_bus)" "$SPOTIFY_NATIVE_MPRIS_BUS"
    printf 'spotify_native_mpris_wait_timeout_seconds\t%s\t15\tinput\n' "$(t spotify_native.field.mpris_wait_timeout_seconds)"
    printf 'spotify_native_sink_match\t%s\t%s\tinput\n' "$(t spotify_native.field.sink_match)" "$SPOTIFY_NATIVE_SINK_MATCH"
}

profile_apply_defaults () {
    spotify_native_manage_player="yes"
    spotify_native_sink_app_name="spotify"
    spotify_native_mpris_bus="$SPOTIFY_NATIVE_MPRIS_BUS"
    spotify_native_mpris_wait_timeout_seconds="15"
    spotify_native_sink_match="$SPOTIFY_NATIVE_SINK_MATCH"
    profile_activate
}

# Copies this module's persisted, prefixed vars into the generic unprefixed
# runtime vars that the main script's sink-detection/routing functions
# (get_target_sink_index, is_target_sink_app, ensure_target_routed) already
# read. Even though this module routes Spotify's audio at launch time (via
# PULSE_SINK, see launch_spotify() below), start_recording() still calls
# ensure_target_routed() on every track, which needs source_sink_index -
# populated only via get_target_sink_index(), which needs these two fields.
profile_activate () {
    sink_app_name="$spotify_native_sink_app_name"
    player_mpris_bus="$spotify_native_mpris_bus"
    player_sink_match="$spotify_native_sink_match"
}

# Required by the 7-hook contract, but genuinely unused: this module never
# routes a non-sink wait through wizard_step_screen (see profile_run()
# below - the MPRIS-appears-after-launch wait needs its own failure screen,
# which wizard_step_screen's hard-coded _cancel_and_exit-on-failure can't
# provide, so it's implemented as a bespoke "gum spin -- bash -c" call
# instead).
profile_wait_condition () {
    case "$1" in
        stopped) _playback_is_stopped ;;
        playing) _playback_is_playing ;;
        *)       return 2 ;;
    esac
}

###############################################################################
# Player profile (MPRIS playback status / bus ownership)
###############################################################################

# True while $player_mpris_bus still has an owner on the bus. Reused for two
# purposes here: the pre-launch "is Spotify already running" guard, and (via
# wait_for_mpris_bus's bash -c poller, which reimplements this exact check
# inline since it runs as a separate process) "has Spotify appeared on MPRIS
# after launch". An empty bus name (a half-configured setup) counts as alive
# so we never treat a broken config as "safe to launch into".
player_bus_has_owner () {
    [[ -n "$player_mpris_bus" ]] || return 0
    dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner "string:$player_mpris_bus" >/dev/null 2>&1
}

# Deliberately NOT a bare player_bus_has_owner call: that one treats an empty
# bus name as "alive" so poll_player_liveness never self-terminates a running
# session on a half-configured setup. Here the same answer would mean "Spotify
# is already running" and refuse to start at all, so an unset bus name has to
# read as "nothing detected" instead.
already_running () {
    [[ -n "$player_mpris_bus" ]] || return 1
    player_bus_has_owner
}

# Called by the main loop on a timer once playback has begun. A plain quit of
# the player sends no Paused/Stopped signal and dbus-monitor keeps running,
# which would leave us recording silence forever; two consecutive misses
# (~a few seconds) end the session the same way a pause does.
poll_player_liveness () {
    [[ "$started_playing" == "true" && $should_exit -eq 0 ]] || return 0
    if player_bus_has_owner; then
        player_missing_polls=0
        return 0
    fi
    player_missing_polls=$((player_missing_polls + 1))
    [[ $player_missing_polls -ge 2 ]] || return 0
    stop_current_recording "drain"
    active_recording_signature=""
    log_line "player exited"
    end_session
}

# One-shot PlaybackStatus query (used by the wizard before the coproc exists).
player_playback_status () {
    dbus-send --print-reply --dest="$player_mpris_bus" /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:org.mpris.MediaPlayer2.Player string:PlaybackStatus 2>/dev/null \
      | awk -F'"' '/string "(Playing|Paused|Stopped)"/{print $2; exit}'
}

_playback_is_playing () {
    [[ "$(player_playback_status)" == "Playing" ]]
}

_playback_is_stopped () {
    [[ "$(player_playback_status)" != "Playing" ]]
}

# Actively queries the player's current MPRIS Metadata and emits it as the same
# "key -> value" lines the coproc produces. This is the recovery path for a
# PropertiesChanged burst that was missed (emitted before the coproc attached)
# or that announced "Playing" without carrying any metadata: without a title
# and artist there is no filename, so recording must never start blind.
_query_metadata_kv () {
    local line expect_key="" expect_type=""
    while IFS= read -r line; do
        _mpris_parse_line "$line" expect_key expect_type
    done < <(dbus-send --print-reply --dest="$player_mpris_bus" /org/mpris/MediaPlayer2 \
                org.freedesktop.DBus.Properties.Get \
                string:org.mpris.MediaPlayer2.Player string:Metadata 2>/dev/null)
}

# Applies a freshly-queried Metadata snapshot into the same globals the coproc
# feeds, so maybe_start_recording can proceed exactly as if the burst had been
# received live. Only ever called while nothing is recording and the fields are
# empty, so it never fights the live stream.
query_current_metadata () {
    local kv
    while IFS= read -r kv; do
        process_dbus_line "$kv"
    done < <(_query_metadata_kv)
}

###############################################################################
# Install detection / launch / URL parsing / playback trigger
###############################################################################

# Sets managed_install_type. Checks, in order: a native "spotify" binary on
# PATH, a Flatpak install of com.spotify.Client, a Snap install of spotify -
# first match wins.
detect_install_type () {
    if command -v spotify >/dev/null 2>&1; then
        managed_install_type="native"; return 0
    fi
    if command -v flatpak >/dev/null 2>&1 && flatpak info "$SPOTIFY_NATIVE_FLATPAK_APP_ID" >/dev/null 2>&1; then
        managed_install_type="flatpak"; return 0
    fi
    if command -v snap >/dev/null 2>&1 && snap list "$SPOTIFY_NATIVE_SNAP_NAME" >/dev/null 2>&1; then
        managed_install_type="snap"; return 0
    fi
    return 1
}

# Backgrounds Spotify with PULSE_SINK already pointed at our capture sink, so
# its very first audio stream lands there directly - no move_target_output
# needed, unlike spotify_native. managed_pid is only meaningful for "native"
# (Flatpak/Snap are torn down by their own mechanism in profile_cleanup, not
# by PID - see there for why).
launch_spotify () {
    # --minimized: this profile drives Spotify over MPRIS and the user never
    # needs to touch its window, so it starts out of the way.
    case "$managed_install_type" in
        native)
            PULSE_SINK="$nulloutput_name" spotify --minimized >/dev/null 2>&1 &
            managed_pid=$!
            ;;
        flatpak)
            PULSE_SINK="$nulloutput_name" flatpak run "$SPOTIFY_NATIVE_FLATPAK_APP_ID" --minimized >/dev/null 2>&1 &
            managed_pid=""
            ;;
        snap)
            PULSE_SINK="$nulloutput_name" snap run "$SPOTIFY_NATIVE_SNAP_NAME" --minimized >/dev/null 2>&1 &
            managed_pid=""
            ;;
    esac
    managed_launched=true
    log_line "launched spotify install_type=$managed_install_type pulse_sink=$nulloutput_name"
}

# Polls $player_mpris_bus for an owner, up to $1 seconds, wrapped in a real
# "gum spin" so the wait animates and Ctrl+C cancels it like any other
# foreground command - a dedicated subprocess (not the shared
# wizard_step_screen) because this wait needs its own
# specific failure screen on timeout, not wizard_step_screen's generic
# _cancel_and_exit. Args are passed positionally into "bash -c", not
# interpolated into the script string, to avoid any quoting hazard.
wait_for_mpris_bus () {
    local timeout="$1"

    render_page "$(t spotify_native.title)" \
        "$(ui_box "$(ui_subtitle "$(t spotify_native.wizard.launch_heading)")" "" \
            "$(t spotify_native.wizard.launch_line1)")"
    ui_gap

    # The single-quoted script below is intentional: $bus/$timeout must
    # expand inside the spawned bash -c (from its own $1/$2), not here.
    # shellcheck disable=SC2016
    gum spin --spinner points --title "$(t spotify_native.wizard.spin_launch)" -- \
        bash -c '
            bus="$1"; timeout="$2"
            deadline=$(( $(date +%s) + timeout ))
            while (( $(date +%s) < deadline )); do
                dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
                    org.freedesktop.DBus.GetNameOwner "string:$bus" >/dev/null 2>&1 && exit 0
                sleep 0.5
            done
            exit 1
        ' _ "$player_mpris_bus" "$timeout"
}

# Spotify's MPRIS bus name can appear before its UI/backend has actually
# finished starting up - a fixed, VISIBLE wait here (a real "gum spin",
# same Spinner element as every other wait in the app) gives it a moment to
# settle before we ask for a URL and call OpenUri, instead of a silent delay
# the user has no feedback for.
wait_for_spotify_to_load () {
    render_page "$(t spotify_native.title)" \
        "$(ui_box "$(ui_subtitle "$(t spotify_native.wizard.loading_heading)")" "" \
            "$(t spotify_native.wizard.loading_line1)")"
    ui_gap

    gum spin --spinner points --title "$(t spotify_native.wizard.spin_loading)" -- sleep 10
}

# Extracts the type (track/album/playlist) and id from a Spotify web URL and
# builds the "spotify:<type>:<id>" URI OpenUri expects. Returns 1 on a URL
# that doesn't match any of the three known shapes.
parse_spotify_url () {
    local url="$1"
    [[ "$url" =~ $SPOTIFY_NATIVE_URL_RE ]] || return 1
    printf 'spotify:%s:%s' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

# Calls MPRIS OpenUri to actually start playback. Retried a few times, a
# second apart: the MPRIS bus name can appear (wait_for_mpris_bus succeeds)
# slightly before Spotify's Player interface is fully wired up, so an
# immediate OpenUri can be rejected even though the player is, moments
# later, genuinely ready. Logged either way so a --debug run has a trail
# even when nothing ever reaches start_recording (e.g. metadata that never
# arrives because playback was never actually triggered).
trigger_playback () {
    local attempt
    for attempt in 1 2 3 4 5; do
        # Ctrl+C during the retries only sets flags - stop retrying instead of
        # holding the user here for the rest of the budget.
        [[ $should_exit -eq 0 ]] || return 1
        if dbus-send --print-reply --dest="$player_mpris_bus" /org/mpris/MediaPlayer2 \
                org.mpris.MediaPlayer2.Player.OpenUri "string:$managed_spotify_uri" >/dev/null 2>&1; then
            log_line "OpenUri succeeded uri=$managed_spotify_uri attempt=$attempt"
            return 0
        fi
        sleep 1
    done
    log_line "OpenUri failed after $attempt attempts uri=$managed_spotify_uri"
    return 1
}

###############################################################################
# Screens
###############################################################################

# Informational/consent screen - shown before anything is detected/launched.
# Ctrl+C is the only other way out; nothing has been created yet, so a plain
# cancel is safe.
requirements_screen () {
    render_page "$(t spotify_native.title)" \
        "$(ui_box \
            "$(ui_subtitle "$(t spotify_native.requirements.attention)")" "" \
            "$(t spotify_native.requirements.body)")"
    ui_gap

    gum choose --header "$(t spotify_native.action.header)" --cursor="$UI_CURSOR" -- \
        "$(t spotify_native.requirements.confirm)" >/dev/null || _cancel_and_exit
}

# Shown for every unrecoverable pre-recording failure (Spotify not installed,
# already running, or never appeared on MPRIS after launch) - the spec calls
# for a specific message plus a single "Exit" choice, never a retry loop.
# $@ are pre-rendered body elements (ui_box/ui_notify). Always exits - the
# already-installed cleanup EXIT trap tears down anything created so far.
fatal_exit_screen () {
    render_page "$(t spotify_native.title)" "$@"
    ui_gap
    gum choose --header "$(t spotify_native.action.header)" --cursor="$UI_CURSOR" -- \
        "$(t spotify_native.action.exit)" >/dev/null || true
    exit 0
}

# URL input, reusing session_name_screen's Notification-driven validation-
# loop shape: render, show any error from the previous attempt, prompt,
# validate, loop with the bad value prefilled on failure.
url_input_screen () {
    local err="" prefill="" value

    while true; do
        render_page "$(t spotify_native.title)" \
            "$(ui_box "$(t spotify_native.url.intro)" "" \
                "$(gum style --bold -- "$(t spotify_native.url.instruction)")")"
        [[ -n "$err" ]] && printf '%s\n' "$(ui_notify "$err")"
        ui_gap

        value="$(gum input --header "$(t spotify_native.url.input_header)" \
                --prompt="$UI_CURSOR" --value "$prefill")" || _cancel_and_exit

        if ! managed_spotify_uri="$(parse_spotify_url "$value")"; then
            err="$(t spotify_native.error.invalid_url)"
            prefill="$value"; continue
        fi
        break
    done
}

###############################################################################
# MPRIS monitor (player-scoped)
###############################################################################

# Extracts the value of a dbus-monitor `string "..."` line. A field split on
# the `"` delimiter (`cut -d '"' -f2`) truncates any value that itself contains
# a quote - e.g. a title like `Always with Me (From "Spirited Away")` was cut
# to `Always with Me (From`. dbus-monitor does not escape embedded quotes, so
# instead take everything between the FIRST `string "` and the LAST `"` on the
# line - the only two quotes guaranteed to be delimiters.
_dbus_string_value () {
    local v="${1#*string \"}"   # drop up to and including the opening: string "
    printf '%s' "${v%\"*}"      # drop the trailing closing quote
}

# Parses ONE line of MPRIS property output, carrying the "which key/type are we
# inside" state across calls in the caller's own $2/$3 variables (by name). It
# emits a "key -> value" line when a full value is seen. The exact same format
# is produced by dbus-monitor's PropertiesChanged stream AND by a one-shot
# `dbus-send ... Properties.Get Metadata` reply, so both parse through here.
_mpris_parse_line () {
    local line="$1"
    local -n _ek="$2" _et="$3"

    case "$line" in
        *'string "PlaybackStatus"'*)     _ek="playbackstatus"; _et="string";       return ;;
        *'string "mpris:trackid"'*)      _ek="trackid";        _et="string";       return ;;
        *'string "xesam:album"'*)        _ek="album";          _et="string";       return ;;
        *'string "xesam:albumArtist"'*)  _ek="albumartist";    _et="string";       return ;;
        *'string "xesam:artist"'*)       _ek="artist";         _et="string_array"; return ;;
        *'string "xesam:discNumber"'*)   _ek="discnumber";     _et="int32";        return ;;
        *'string "xesam:title"'*)        _ek="title";          _et="string";       return ;;
        *'string "xesam:trackNumber"'*)  _ek="tracknumber";    _et="int32";        return ;;
    esac

    [[ -z "$_ek" ]] && return

    if [[ "$_et" == "string" ]] && [[ $line == *'string "'* ]]; then
        printf '%s -> %s\n' "$_ek" "$(_dbus_string_value "$line")"
        _ek=""; _et=""
    elif [[ "$_et" == "string_array" ]] && [[ $line == *']'* ]]; then
        # End of the "xesam:artist" array (a bare "]" line) - stop
        # matching further elements, without emitting a bogus one.
        _ek=""; _et=""
    elif [[ "$_et" == "string_array" ]] && [[ $line == *'string "'* ]]; then
        # One element of the "xesam:artist" array - unlike a scalar
        # "string" field, do NOT clear the state here, so every remaining
        # element up to the closing "]" is also emitted under "artist".
        printf '%s -> %s\n' "$_ek" "$(_dbus_string_value "$line")"
    elif [[ "$_et" == "int32" ]] && [[ $line == *'int32 '* ]]; then
        # Value sits after the LAST "int32 " token, not at a fixed
        # field position - the "variant" prefix column width varies.
        printf '%s -> %s\n' "$_ek" "${line##*int32 }"
        _ek=""; _et=""
    fi
}

# Runs as a coproc. Emits "key -> value" lines parsed by process_dbus_line.
# If the player-scoped match rule is rejected, retries once unscoped.
get_dbusmessages () {
    local rule="$1"
    local fallback="path=/org/mpris/MediaPlayer2,member=PropertiesChanged"
    local expect_key="" expect_type="" line started=0 attempt=0

    while :; do
        attempt=$((attempt + 1))
        expect_key=""; expect_type=""
        while IFS= read -r line; do
            started=1
            _mpris_parse_line "$line" expect_key expect_type
        done < <(dbus-monitor "$rule" 2>/dev/null)

        # dbus-monitor exited with no output at all -> the rule was rejected.
        # Retry once, unscoped (degraded: other MPRIS players may bleed in).
        if [[ $started -eq 0 && $attempt -eq 1 && "$rule" != "$fallback" ]]; then
            rule="$fallback"
            continue
        fi
        break
    done
}

# A single MPRIS Metadata update arrives as one burst of lines, and the order
# of the keys inside it is whatever the dict happened to hold - NOT fixed. So
# the "new track" reset has to be taken once for the whole burst, before any
# of it is applied: doing it per line meant a trackid landing after title and
# artist wiped the very fields that same burst had just delivered, and the
# track then recorded with no metadata at all. Intermittent exactly because
# the key order is not guaranteed, and it looked like a first-track-only
# problem because later tracks get further Metadata updates that refresh the
# fields without changing trackid.
_apply_track_change () {
    local line id=""
    for line in "$@"; do
        [[ "$line" == 'trackid -> '* ]] && id="${line#trackid -> }"
    done
    [[ -n "$id" && "$id" != "$last_trackid" ]] || return 0

    last_trackid="$id"
    active_recording_signature=""
    title="" artist="" album="" albumartist="" tracknumber="" discnumber=""
    artist_all=()
    stop_current_recording
}

maybe_start_recording () {
    local signature

    [[ "$playbackstatus" != "Playing" ]] && return

    # There is no filename without metadata, so a missed/empty burst must not be
    # silently accepted: query the player directly before giving up. If it still
    # yields nothing (e.g. between tracks), stay idle and let the next tick retry.
    [[ -z "$title" || -z "$artist" ]] && query_current_metadata
    [[ -z "$title" || -z "$artist" ]] && return

    signature="${trackid:-$artist|$album|$title}"
    [[ "$signature" == "$active_recording_signature" ]] && return

    if start_recording "$artist" "$album" "$title" "$albumartist" "$tracknumber" "$discnumber"; then
        active_recording_signature="$signature"
        # Keep track-change detection in sync with a recording started from a
        # recovered (not live-streamed) burst, so a later refresh of the SAME
        # track does not read as a change and needlessly split the file.
        [[ -n "$trackid" ]] && last_trackid="$trackid"
    fi
}

process_dbus_line () {
    local dbus_read="$1"

    # None of the branches below decide whether to (re)start recording - that
    # happens once per drain batch, in recording_main_loop, after every
    # currently-buffered line has been applied (a single MPRIS metadata
    # update emits its keys as several consecutive lines; trackNumber in
    # particular is emitted after title).
    case "$dbus_read" in
        'playbackstatus -> '*)
            playbackstatus="${dbus_read#playbackstatus -> }"
            status_dirty=1
            if [[ "$playbackstatus" == "Playing" ]]; then
                started_playing=true
            elif [[ "$started_playing" == "true" ]]; then
                # Any non-Playing state after playback began ends the session
                # (no half tracks; also where Spotify lands when a playlist
                # finishes). A pause before the first Playing is ignored.
                stop_current_recording "drain"
                active_recording_signature=""
                end_session
            fi
            ;;
        'trackid -> '*)
            # Only recorded here. Reacting to a track CHANGE is a per-burst
            # decision, not a per-line one - see _apply_track_change below.
            trackid="${dbus_read#trackid -> }"
            ;;
        'title -> '*)       title="${dbus_read#title -> }";             tui_set "track" "$title" ;;
        'artist -> '*)
            local _artist_value="${dbus_read#artist -> }"
            # First xesam:artist element of this track becomes the scalar
            # "artist" (naming/log/AAC tag); every element - first included -
            # is also collected into artist_all (table display/OGG tags).
            [[ ${#artist_all[@]} -eq 0 ]] && artist="$_artist_value"
            artist_all+=("$_artist_value")
            tui_set "artist" "$(join_artist_list)"
            ;;
        'album -> '*)       album="${dbus_read#album -> }";             tui_set "album" "$album" ;;
        'albumartist -> '*) albumartist="${dbus_read#albumartist -> }" ;;
        'tracknumber -> '*) tracknumber="${dbus_read#tracknumber -> }" ;;
        'discnumber -> '*)  discnumber="${dbus_read#discnumber -> }" ;;
    esac
}

# Every captured xesam:artist value, joined with "; " - used for the
# Metadata table and for OGG tagging (which writes them back out as separate
# ARTIST= comment fields). Naming, the session log, and the AAC tag use only
# the first value (the scalar "artist"), never this.
join_artist_list () {
    local joined="" a
    for a in "${artist_all[@]}"; do
        [[ -z "$joined" ]] && joined="$a" || joined="$joined; $a"
    done
    printf '%s' "$joined"
}

###############################################################################
# Recording screen
###############################################################################

recording_screen_render () {
    [[ -t 1 ]] || return

    local info meta frame catcher_status
    catcher_status="$(t spotify_native.status.recording)"
    [[ "$recording_failed" == "true" ]] && catcher_status="$(t spotify_native.status.failed)"

    # Session facts as plain "Label: value" lines in one Normal element, not a
    # table: three values do not earn a bordered table, and this screen is the
    # one that has to fit on a terminal.
    info="$(ui_box "$(ui_kv_lines \
        "$(t spotify_native.field.output_folder)" "$(clip_text "${output_directory:--}")" \
        "$(t spotify_native.field.session_name)" "$(clip_text "${session_name:--}")" \
        "$(t spotify_native.field.catcher_status)" "$catcher_status")")"

    meta="$(ui_kv_table "$(t common.table.field)" "$(t common.table.value)" \
        "$(t spotify_native.field.artist)" "$(clip_text "${tui_artist:--}")" \
        "$(t spotify_native.field.album)" "$(clip_text "${tui_album:--}")" \
        "$(t spotify_native.field.track)" "$(clip_text "${tui_track:--}")")"

    local meta_heading
    meta_heading="$(ui_subtitle "$(t spotify_native.recording.metadata_heading)" "$UI_WIDTH")"

    printf -v frame '%s\n%s\n%s\n%s\n' \
        "$(ui_title_row "$(t spotify_native.recording.title)")" "$info" "$meta_heading" "$meta"

    paint_frame "$frame"
    ui_gap

}

recording_main_loop () {
    # Snapshot the coproc fd: bash may unset the DBUS_MONITOR array once the
    # coprocess exits, and "set -u" would then abort on ${DBUS_MONITOR[0]}.
    local dbus_fd="${DBUS_MONITOR[0]}"
    local dbus_read last_liveness=$SECONDS tick=0 catching
    catching="$(t ui.catching)"   # resolved once: the loop ticks five times a second

    while [[ $should_exit -eq 0 ]]; do
        if ! kill -0 "$dbus_monitor_pid" 2>/dev/null; then
            exit_note="$(t spotify_native.error.dbus_monitor_ended)"
            break
        fi

        # Read the whole burst first, then apply it: a metadata burst
        # (trackid + title + artist + album) is one event, so it collapses
        # into ONE repaint and ONE recording decision - and the track change
        # is settled before any of the burst's own values are applied.
        local -a batch=()
        while IFS= read -r -t 0.2 -u "$dbus_fd" dbus_read 2>/dev/null; do
            batch+=("$dbus_read")
            [[ $should_exit -eq 0 ]] || break
        done

        if [[ ${#batch[@]} -gt 0 && $should_exit -eq 0 ]]; then
            _apply_track_change "${batch[@]}"
            for dbus_read in "${batch[@]}"; do
                process_dbus_line "$dbus_read"
            done
            maybe_start_recording
        fi

        # Catch a player that quit outright (no Paused/Stopped signal reaches
        # the still-running dbus-monitor). Polled every second, and it still
        # takes two consecutive misses to act, so a closed player ends the
        # session in ~2s instead of ~4s without trusting a single hiccup.
        if [[ $should_exit -eq 0 && $(( SECONDS - last_liveness )) -ge 1 ]]; then
            last_liveness=$SECONDS
            poll_player_liveness
            # Recover a missed Metadata burst: if playback is running but nothing
            # is recording yet, the "Playing" signal arrived without usable
            # metadata (or its burst never reached us). maybe_start_recording
            # then queries the player directly. Throttled to this 1s tick and
            # gated on an empty signature, so it stops the instant recording
            # begins and never floods dbus.
            if [[ $should_exit -eq 0 && "$playbackstatus" == "Playing" && -z "$active_recording_signature" ]]; then
                maybe_start_recording
            fi
        fi

        # The frame is only recomposed when something changed - composing it
        # shells out to gum, so doing it every tick would make the screen
        # sluggish. The spinner is just one character, so it ticks always.
        if [[ $status_dirty -eq 1 && $should_exit -eq 0 ]]; then
            status_dirty=0
            recording_screen_render
        fi
        tick=$((tick + 1))
        [[ $should_exit -eq 0 ]] && ui_spinner_tick "$tick" "$catching"
    done
}

###############################################################################
# Per-session entry point (profile_run)
###############################################################################

# The two ways this profile can work, chosen by the manage_player setting.
# Everything after them - the MPRIS monitor, the Recording screen and the
# recording loop - is identical, which is why these are two functions and not
# two modules: keeping them apart meant maintaining 211 lines of byte-for-byte
# duplicate machinery.
_run_managed () {
    requirements_screen

    detect_install_type || fatal_exit_screen "$(ui_box \
        "$(t spotify_native.error.not_installed_body)")"

    already_running && fatal_exit_screen "$(ui_box \
        "$(t spotify_native.error.already_running)")"

    # The null sink must exist BEFORE Spotify's very first stream is created:
    # PULSE_SINK is resolved by sink name at stream-creation time, so this
    # order is load-bearing - unlike spotify_native, which routes an
    # already-existing stream after the fact (move_target_output), this
    # module never needs to move anything.
    create_null_audio_output
    launch_spotify

    local mpris_timeout="$spotify_native_mpris_wait_timeout_seconds"
    [[ "$mpris_timeout" =~ ^[0-9]+$ ]] || mpris_timeout=15
    if ! wait_for_mpris_bus "$mpris_timeout"; then
        # Ctrl+C during the wait lands here too (gum spin returns non-zero),
        # but that is a cancel, not a timeout - don't blame Spotify for it.
        [[ $should_exit -eq 0 ]] || _cancel_and_exit
        fatal_exit_screen "$(ui_box \
            "$(t spotify_native.error.mpris_timeout "$mpris_timeout")")"
    fi

    # GetNameOwner succeeding only proves the bus NAME is claimed, not that
    # the Player interface's methods are already wired up - Spotify can
    # register org.mpris.MediaPlayer2.spotify slightly before it's ready to
    # actually service OpenUri. This visible wait (still before the coproc
    # starts listening, so nothing is missed) makes that narrow startup race
    # far less likely to reach trigger_playback's own retries, and gives the
    # user feedback for what would otherwise be a silent pause.
    wait_for_spotify_to_load
    # Ctrl+C during that wait fires main()'s INT trap, which only sets flags -
    # without this the flow would carry straight on and ask for a URL as if
    # nothing had happened.
    [[ $should_exit -eq 0 ]] || _cancel_and_exit

    # Start listening BEFORE OpenUri (this module's own equivalent of "the
    # user presses Play") - MPRIS emits PlaybackStatus/metadata only once, at
    # the transition. Critical ordering, do not move - same rule spotify_native
    # documents for its own step2->step3 boundary.
    coproc DBUS_MONITOR { get_dbusmessages "path=/org/mpris/MediaPlayer2,member=PropertiesChanged,sender=$player_mpris_bus"; }
    dbus_monitor_pid=$!

    url_input_screen

    trigger_playback || fatal_exit_screen "$(ui_box \
        "$(t spotify_native.error.openuri_failed)")"

    # Block here, visibly, until Spotify's own sink-input actually exists and
    # is matched by name - exactly the same wizard step spotify_native uses
    # for its own (already-running) player, via the same generic "sink" kind
    # wizard_step_screen already special-cases (an unbounded retry loop, not a
    # single attempt). This closes the buffering/loading gap between
    # "MPRIS says Playing" and "the PulseAudio stream actually exists" -
    # ensure_target_routed()'s own retry inside start_recording is a single
    # attempt, so leaving this to chance made the very first track's
    # recording fail outright whenever the sink-input hadn't registered yet.
    if ! get_target_sink_index; then
        wizard_step_screen 1 sink "$(t spotify_native.wizard.sink_heading)" \
            "$(t spotify_native.wizard.sink_line1)"
        get_target_sink_index || true
    fi
    log_line "resolved audio sink index=${source_sink_index:-<none>}"
}

# The user opens, pauses and cues Spotify themselves; we only attach to it.
_run_attached () {
    local label
    label="$(profile_label)"

    if ! get_target_sink_index; then
        wizard_step_screen 1 sink "$(t spotify_native.wizard.step1_heading)" \
            "$(t spotify_native.wizard.step1_body "$label")"
        get_target_sink_index || true
    fi

    # Route the sink-input into our capture sink as soon as it's known -
    # NOT after the user presses Play in step 3. Routing this late meant the
    # first milliseconds of the first track played out the real speakers
    # (and were lost to capture) instead of already flowing into our null
    # sink's monitor by the time Playing arrives. Critical ordering, do not
    # move: this must happen right after step 1, before steps 2/3.
    create_null_audio_output
    move_target_output

    if ! _playback_is_stopped; then
        wizard_step_screen 2 stopped "$(t spotify_native.wizard.step2_heading)" \
            "$(t spotify_native.wizard.step2_line1 "$label")"
    fi

    # By this point playback is confirmed paused/stopped (step 2 guaranteed it,
    # or it already was). Start listening for MPRIS signals now, before the
    # user presses Play again, so the Playing transition and the first track's
    # metadata - both one-shot signals - are not missed. Critical ordering,
    # do not move: see AGENTS.md.
    coproc DBUS_MONITOR { get_dbusmessages "path=/org/mpris/MediaPlayer2,member=PropertiesChanged,sender=$player_mpris_bus"; }
    dbus_monitor_pid=$!

    if ! _playback_is_playing; then
        wizard_step_screen 3 playing "$(t spotify_native.wizard.step3_heading)" \
            "$(t spotify_native.wizard.step3_line1)"
    fi
}

profile_run () {
    if [[ "$spotify_native_manage_player" == "no" ]]; then
        _run_attached
    else
        _run_managed
    fi

    # The Recording screen is only ever shown while a session is underway;
    # Catcher Status starts "Recording" (recording_failed defaults false).
    screen_enter
    trap 'status_dirty=1' WINCH

    status_dirty=0
    recording_screen_render

    recording_main_loop
}

# Bounded (~2s) wait for a PID to actually exit after a signal, since a GUI
# app commonly takes a moment (or, for SIGINT specifically, may just ignore
# it outright - most GUI toolkits don't treat SIGINT as "please quit") to
# actually go away.
_wait_for_pid_exit () {
    local pid="$1" i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.2
    done
    return 1
}

# Same idea, for Flatpak/Snap where we have no PID to poll: bounded (~2s)
# wait for $player_mpris_bus to lose its owner, our best proxy for "the
# Spotify process actually quit" without a PID to check directly.
_wait_for_mpris_gone () {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        player_bus_has_owner || return 0
        sleep 0.2
    done
    return 1
}

profile_cleanup () {
    if [[ -n "$dbus_monitor_pid" ]] && kill -0 "$dbus_monitor_pid" 2>/dev/null; then
        kill "$dbus_monitor_pid" 2>/dev/null || true
    fi

    # Nothing below may run unless this module actually started Spotify: on
    # the "already running" exit path the install type is known but the live
    # instance belongs to the user, and closing it would contradict the very
    # message that screen just showed them.
    [[ "$managed_launched" == "true" ]] || return 0

    # Per-install-type teardown of the Spotify process this module launched.
    # Verifies the process actually went away (bounded wait) and escalates
    # once before giving up - a plain SIGTERM/"flatpak kill"/pkill can be
    # ignored outright by a GUI app (this is common: most GUI toolkits don't
    # treat SIGINT/SIGTERM as "quit" the way CLI tools do), which previously
    # left Spotify running - and playing/recording, from the user's point of
    # view - even though loopcatcher itself had already torn down and exited.
    # Still best-effort overall: if the escalation also fails, log it and
    # move on, no error surfaced to the user (see AGENTS.md's teardown note).
    case "$managed_install_type" in
        native)
            if [[ -n "$managed_pid" ]] && kill -0 "$managed_pid" 2>/dev/null; then
                kill "$managed_pid" 2>/dev/null || true
                if _wait_for_pid_exit "$managed_pid"; then
                    log_line "closed spotify (native, pid=$managed_pid)"
                else
                    kill -9 "$managed_pid" 2>/dev/null || true
                    log_line "spotify (native, pid=$managed_pid) ignored SIGTERM, sent SIGKILL"
                fi
            fi
            ;;
        flatpak)
            flatpak kill "$SPOTIFY_NATIVE_FLATPAK_APP_ID" >/dev/null 2>&1 || true
            if _wait_for_mpris_gone; then
                log_line "closed spotify (flatpak)"
            else
                pkill -f "$SPOTIFY_NATIVE_FLATPAK_APP_ID" >/dev/null 2>&1 || true
                log_line "flatpak kill did not stop spotify in time, fell back to pkill"
            fi
            ;;
        snap)
            # There is no real "snap kill <app>" subcommand in snapd - match
            # the resolved snap binary path instead.
            pkill -f "/snap/$SPOTIFY_NATIVE_SNAP_NAME/" >/dev/null 2>&1 || true
            if _wait_for_mpris_gone; then
                log_line "closed spotify (snap)"
            else
                pkill -9 -f "/snap/$SPOTIFY_NATIVE_SNAP_NAME/" >/dev/null 2>&1 || true
                log_line "spotify (snap) ignored pkill, sent pkill -9"
            fi
            ;;
    esac
}
