#!/usr/bin/env bash
###############################################################################
# spotify_native profile module for loopcatcher.
#
# Detects and captures the official Spotify Linux client via its MPRIS
# interface. This file is `source`d directly into the main script's process
# by load_profile_module() - never executed on its own - so it shares the
# main script's global namespace and can call any of its generic helpers
# (wizard_step_screen, get_target_sink_index, ensure_target_routed,
# create_null_audio_output, move_target_output, screen_enter/screen_leave,
# start_recording, stop_current_recording, end_session, tui_set,
# status_output_relpath, log_line/log_debug, ui_kv_table, paint_frame, ...).
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

# --- persisted to the config file, prefixed spotify_native_* ---
# Deliberately NOT self-defaulted here (e.g. via "${var:-default}"): load_config
# checks whether these are already set - by the config file it just sourced -
# to decide whether this module needs seeding via profile_apply_defaults(). A
# self-default here would make that check always true and defeat it.

# --- MPRIS monitor / recording-loop state (not persisted) ---
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

###############################################################################
# Module hook contract
###############################################################################

profile_label () {
    t spotify_native.label
}

# One row per config field: key<TAB>label<TAB>default<TAB>kind[<TAB>choices]
# "kind" is "input" or "choice" (choices space-separated in the 5th field) -
# drives both the generic Profile Settings editor and config-seeding. Labels
# come from this module's own lang/ files (t spotify_native.field.*), not
# the main lang/en.sh - see the comment at the top of lang/en.sh for why.
profile_config_schema () {
    printf 'spotify_native_sink_app_name\t%s\tspotify\tinput\n' "$(t spotify_native.field.sink_app_name)"
    printf 'spotify_native_mpris_bus\t%s\t%s\tinput\n' "$(t spotify_native.field.mpris_bus)" "$SPOTIFY_NATIVE_MPRIS_BUS"
    printf 'spotify_native_sink_match\t%s\t%s\tinput\n' "$(t spotify_native.field.sink_match)" "$SPOTIFY_NATIVE_SINK_MATCH"
}

profile_apply_defaults () {
    spotify_native_sink_app_name="spotify"
    spotify_native_mpris_bus="$SPOTIFY_NATIVE_MPRIS_BUS"
    spotify_native_sink_match="$SPOTIFY_NATIVE_SINK_MATCH"
    profile_activate
}

# Copies this module's persisted, prefixed vars into the generic unprefixed
# runtime vars that the main script's sink-detection/routing functions
# (get_target_sink_index, is_target_sink_app, ensure_target_routed) - and
# this module's own MPRIS helpers below - already read. Keeps both sides of
# the module boundary untouched; only where these vars get POPULATED changes.
profile_activate () {
    sink_app_name="$spotify_native_sink_app_name"
    player_mpris_bus="$spotify_native_mpris_bus"
    player_sink_match="$spotify_native_sink_match"
}

# Used by _internal_wait for any wizard-step kind other than the generic
# "sink" (handled directly by the main script, since every profile needs one).
profile_wait_condition () {
    case "$1" in
        stopped) _playback_is_stopped ;;
        playing) _playback_is_playing ;;
        *)       return 1 ;;
    esac
}

###############################################################################
# Player profile (MPRIS playback status)
###############################################################################

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

# True while the player's MPRIS name still has an owner on the bus. Closing the
# player releases the name but emits no PropertiesChanged, so poll_player_liveness
# checks this to end a session whose player quit outright. An empty bus name (a
# half-configured setup) counts as alive so we never self-terminate.
player_bus_has_owner () {
    [[ -n "$player_mpris_bus" ]] || return 0
    dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner "string:$player_mpris_bus" >/dev/null 2>&1
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

###############################################################################
# MPRIS monitor (player-scoped)
###############################################################################

# Runs as a coproc. Emits "key -> value" lines parsed by process_dbus_line.
# If the player-scoped match rule is rejected, retries once unscoped.
get_dbusmessages () {
    local rule="$1"
    local fallback="path=/org/mpris/MediaPlayer2,member=PropertiesChanged"
    local expect_key="" expect_type="" line started=0 attempt=0

    while :; do
        attempt=$((attempt + 1))
        while IFS= read -r line; do
            started=1
            case "$line" in
                *'string "PlaybackStatus"'*)     expect_key="playbackstatus"; expect_type="string"; continue ;;
                *'string "mpris:trackid"'*)      expect_key="trackid";        expect_type="string"; continue ;;
                *'string "xesam:album"'*)        expect_key="album";          expect_type="string"; continue ;;
                *'string "xesam:albumArtist"'*)  expect_key="albumartist";    expect_type="string";       continue ;;
                *'string "xesam:artist"'*)       expect_key="artist";         expect_type="string_array";  continue ;;
                *'string "xesam:discNumber"'*)   expect_key="discnumber";     expect_type="int32";  continue ;;
                *'string "xesam:title"'*)        expect_key="title";          expect_type="string"; continue ;;
                *'string "xesam:trackNumber"'*)  expect_key="tracknumber";    expect_type="int32";  continue ;;
            esac

            [[ -z "$expect_key" ]] && continue

            if [[ "$expect_type" == "string" ]] && [[ $line == *'string "'* ]]; then
                printf '%s -> %s\n' "$expect_key" "$(cut -d '"' -f2 <<< "$line")"
                expect_key=""; expect_type=""
            elif [[ "$expect_type" == "string_array" ]] && [[ $line == *']'* ]]; then
                # End of the "xesam:artist" array (a bare "]" line) - stop
                # matching further elements, without emitting a bogus one.
                expect_key=""; expect_type=""
            elif [[ "$expect_type" == "string_array" ]] && [[ $line == *'string "'* ]]; then
                # One element of the "xesam:artist" array - unlike a scalar
                # "string" field, do NOT clear expect_key/expect_type here,
                # so every remaining element up to the closing "]" is also
                # emitted under the same "artist" key.
                printf '%s -> %s\n' "$expect_key" "$(cut -d '"' -f2 <<< "$line")"
            elif [[ "$expect_type" == "int32" ]] && [[ $line == *'int32 '* ]]; then
                # Value sits after the LAST "int32 " token, not at a fixed
                # field position - the "variant" prefix column width varies.
                printf '%s -> %s\n' "$expect_key" "${line##*int32 }"
                expect_key=""; expect_type=""
            fi
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

maybe_start_recording () {
    local signature

    [[ "$playbackstatus" != "Playing" ]] && return
    [[ -z "$title" || -z "$artist" ]] && return

    signature="${trackid:-$artist|$album|$title}"
    [[ "$signature" == "$active_recording_signature" ]] && return

    if start_recording "$artist" "$album" "$title" "$albumartist" "$tracknumber" "$discnumber"; then
        active_recording_signature="$signature"
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
            trackid="${dbus_read#trackid -> }"
            if [[ "$trackid" != "$last_trackid" ]]; then
                last_trackid="$trackid"
                active_recording_signature=""
                title="" artist="" album="" albumartist="" tracknumber="" discnumber=""
                artist_all=()
                stop_current_recording
            fi
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
        'tracknumber -> '*) tracknumber="${dbus_read#tracknumber -> }"; tui_set "tracknumber" "$tracknumber" ;;
        'discnumber -> '*)  discnumber="${dbus_read#discnumber -> }";   tui_set "discnumber" "$discnumber" ;;
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
    _kill_spinner

    local info meta status frame catcher_status
    catcher_status="$(t spotify_native.status.recording)"
    [[ "$recording_failed" == "true" ]] && catcher_status="$(t spotify_native.status.failed)"

    info="$(ui_kv_table "$(t spotify_native.table.info)" '' \
        "$(t spotify_native.field.output_folder)" "$(clip_text "${output_directory:--}")" \
        "$(t spotify_native.field.session_name)" "$(clip_text "${session_name:--}")" \
        "$(t spotify_native.field.config_file)" "$(clip_text "$config_path")" \
        "$(t spotify_native.field.audio_sink)" "${source_sink_index:--}")"

    meta="$(ui_kv_table "$(t spotify_native.table.metadata)" '' \
        "$(t spotify_native.field.artist)" "$(clip_text "${tui_artist:--}")" \
        "$(t spotify_native.field.album)" "$(clip_text "${tui_album:--}")" \
        "$(t spotify_native.field.track)" "$(clip_text "${tui_track:--}")" \
        "$(t spotify_native.field.track_no)" "$(clip_text "${tui_tracknumber:--}")" \
        "$(t spotify_native.field.disc_no)" "$(clip_text "${tui_discnumber:--}")" \
        "$(t spotify_native.field.output_file)" "$(clip_text "$(status_output_relpath)")")"

    # Playback Status is printed exactly as MPRIS reports it (Playing/Paused/
    # Stopped/...), with no relabelling/translation - only the field LABEL is
    # translated below, never the raw MPRIS value.
    status="$(ui_kv_table "$(t spotify_native.table.status)" '' \
        "$(t spotify_native.field.catcher_status)" "$catcher_status" \
        "$(t spotify_native.field.playback_status)" "$playbackstatus")"

    printf -v frame '%s\n%s\n%s\n%s\n' \
        "$(ui_title_row "$(t spotify_native.recording.title)")" "$info" "$meta" "$status"

    paint_frame "$frame"
    ui_gap

    gum spin --spinner dot --title "$(t spotify_native.status.spinner_suffix "$catcher_status")" -- sleep 999999 &
    _spinner_pid=$!
}

recording_main_loop () {
    # Snapshot the coproc fd: bash may unset the DBUS_MONITOR array once the
    # coprocess exits, and "set -u" would then abort on ${DBUS_MONITOR[0]}.
    local dbus_fd="${DBUS_MONITOR[0]}"
    local dbus_read last_liveness=$SECONDS

    while [[ $should_exit -eq 0 ]]; do
        if ! kill -0 "$dbus_monitor_pid" 2>/dev/null; then
            exit_note="$(t spotify_native.error.dbus_monitor_ended)"
            break
        fi

        # Drain every line already buffered before repainting, so a metadata
        # burst (trackid + title + artist + album) collapses into ONE repaint.
        local dbus_activity=0
        while IFS= read -r -t 0.2 -u "$dbus_fd" dbus_read 2>/dev/null; do
            process_dbus_line "$dbus_read"
            dbus_activity=1
            [[ $should_exit -eq 0 ]] || break
        done

        # Decide once per drain batch, after every buffered key of the burst
        # has been applied - not per key line.
        [[ $dbus_activity -eq 1 && $should_exit -eq 0 ]] && maybe_start_recording

        # Catch a player that quit outright (no Paused/Stopped signal reaches
        # the still-running dbus-monitor). Checked on a ~2s wall-clock timer.
        if [[ $should_exit -eq 0 && $(( SECONDS - last_liveness )) -ge 2 ]]; then
            last_liveness=$SECONDS
            poll_player_liveness
        fi

        # One repaint per tick, only when something changed.
        if [[ $status_dirty -eq 1 && $should_exit -eq 0 ]]; then
            status_dirty=0
            recording_screen_render
        fi
    done
}

###############################################################################
# Per-session entry point (profile_run)
###############################################################################

profile_run () {
    local label
    label="$(profile_label)"

    if ! get_target_sink_index; then
        wizard_step_screen 1 points sink "$(t spotify_native.wizard.step1_heading)" \
            "$(t spotify_native.wizard.step1_line1 "$label")" \
            "$(t spotify_native.wizard.step1_line2)"
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
        wizard_step_screen 2 points stopped "$(t spotify_native.wizard.step2_heading)" \
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
        wizard_step_screen 3 points playing "$(t spotify_native.wizard.step3_heading)" \
            "$(t spotify_native.wizard.step3_line1)"
    fi

    # The Recording screen is only ever shown while a session is underway;
    # Catcher Status starts "Recording" (recording_failed defaults false).
    screen_enter
    trap 'status_dirty=1' WINCH

    status_dirty=0
    recording_screen_render

    recording_main_loop

    _kill_spinner
}

profile_cleanup () {
    if [[ -n "$dbus_monitor_pid" ]] && kill -0 "$dbus_monitor_pid" 2>/dev/null; then
        kill "$dbus_monitor_pid" 2>/dev/null || true
    fi
}
