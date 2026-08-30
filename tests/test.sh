#!/usr/bin/env bash

# shellcheck shell=bash

set -u

ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
SCRIPT_PATH="$ROOT_DIR/loopcatcher"

# shellcheck disable=SC1090

pass_count=0
fail_count=0

pass () {
    pass_count=$((pass_count + 1))
    printf '[PASS] %s\n' "$1"
}

fail () {
    fail_count=$((fail_count + 1))
    printf '[FAIL] %s\n' "$1"
}

assert_contains () {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]]
}

test_help_contains_long_options () {
    local out
    out="$($SCRIPT_PATH --help 2>&1)"

    assert_contains "$out" "--help" || return 1
    assert_contains "$out" "--version" || return 1
    assert_contains "$out" "--output" || return 1
    assert_contains "$out" "--session" || return 1
}

test_invalid_format_rejected () {
    local out
    set +e
    out="$($SCRIPT_PATH --format mp3 2>&1)"
    local status=$?
    set -e

    [[ $status -ne 0 ]] || return 1
    assert_contains "$out" "Invalid --format value"
}

test_invalid_scheme_rejected () {
    local out
    set +e
    out="$($SCRIPT_PATH --scheme bad 2>&1)"
    local status=$?
    set -e

    [[ $status -ne 0 ]] || return 1
    assert_contains "$out" "Invalid --scheme value"
}

test_file_path_structure_and_uniqueness () {
    local out1 out2
    local tmpdir
    tmpdir="$(mktemp -d)"

    # shellcheck disable=SC2034
    out1="$({ source "$SCRIPT_PATH"; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "Artist" "Album" "Song" "m4a"; })"
    [[ "$out1" == *"Artist/Album/Song.m4a" ]] || return 1

    touch "$out1"

    # shellcheck disable=SC2034
    out2="$({ source "$SCRIPT_PATH"; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "Artist" "Album" "Song" "m4a"; })"
    [[ "$out2" == *"Artist/Album/Song_2.m4a" ]] || return 1

    rm -rf "$tmpdir"
}

test_pause_stops_session () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        started_playing=true
        playbackstatus="Playing"
        process_dbus_line "playbackstatus -> Paused"
        printf '%s|%s' "$should_exit" "$session_ended"
    })"

    [[ "$out" == "1|true" ]]
}

test_pause_before_first_play_does_not_exit () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        started_playing=false
        process_dbus_line "playbackstatus -> Paused"
        printf '%s|%s' "$should_exit" "$session_ended"
    })"

    [[ "$out" == "0|false" ]]
}

test_end_session_sets_flags () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        should_exit=0
        session_ended=false
        end_session
        printf '%s|%s' "$should_exit" "$session_ended"
    })"

    [[ "$out" == "1|true" ]]
}

test_normal_scheme_keeps_unicode () {
    local out
    local tmpdir
    tmpdir="$(mktemp -d)"

    # shellcheck disable=SC2034
    out="$({ source "$SCRIPT_PATH"; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "Sigur Rós" "Ágætis byrjun" "Starálfur" "m4a"; })"
    rm -rf "$tmpdir"

    [[ "$out" == *"/Sigur Rós/Ágætis byrjun/Starálfur.m4a" ]]
}

test_normal_scheme_strips_path_chars () {
    local out
    local tmpdir
    tmpdir="$(mktemp -d)"

    # shellcheck disable=SC2034
    out="$({ source "$SCRIPT_PATH"; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "AC/DC" "Album:1" "Song?" "m4a"; })"
    rm -rf "$tmpdir"

    [[ "$out" == *"/AC_DC/Album_1/Song_.m4a" ]]
}

test_track_change_resets_metadata () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        title="Old Title"
        artist="Old Artist"
        artist_all=("Old Artist" "Old Featured Artist")
        album="Old Album"
        last_trackid="track-old"
        playbackstatus="Playing"
        process_dbus_line "trackid -> track-new"
        printf '%s|%s|%s|%s|%s' "$title" "$artist" "$album" "$active_recording_signature" "${#artist_all[@]}"
    })"

    [[ "$out" == "||||0" ]]
}

test_get_dbusmessages_parses_int32_values () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        dbus-monitor () {
            cat <<'EOF'
   dict entry(
      string "xesam:discNumber"
      variant             int32 1
   )
   dict entry(
      string "xesam:trackNumber"
      variant             int32 3
   )
EOF
        }
        get_dbusmessages "unused-rule"
    })"

    [[ "$out" == "$(printf 'discnumber -> 1\ntracknumber -> 3')" ]]
}

test_get_dbusmessages_parses_multiple_artist_values () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        dbus-monitor () {
            cat <<'EOF'
   dict entry(
      string "xesam:artist"
      variant             array [
            string "Metallica"
            string "Apocalyptica"
         ]
   )
   dict entry(
      string "xesam:album"
      variant             string "S&M"
   )
EOF
        }
        get_dbusmessages "unused-rule"
    })"

    [[ "$out" == "$(printf 'artist -> Metallica\nartist -> Apocalyptica\nalbum -> S&M')" ]]
}

test_process_dbus_line_collects_all_artist_values () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        process_dbus_line "artist -> Metallica"
        process_dbus_line "artist -> Apocalyptica"
        printf '%s|%s|%s' "$artist" "${#artist_all[@]}" "$(join_artist_list)"
    })"

    [[ "$out" == "Metallica|2|Metallica; Apocalyptica" ]]
}

test_start_recording_ogg_writes_all_artists_as_separate_fields () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        ensure_target_routed () { return 0; }
        # shellcheck disable=SC2317
        oggenc () { printf '%s\n' "$@" > "$tmpdir/oggenc.args"; sleep 5; }
        # shellcheck disable=SC2317
        parec () { sleep 5; }
        session_output_directory="$tmpdir"
        record_format="ogg"
        artist_all=("Metallica" "Apocalyptica")
        start_recording "Metallica" "S&M" "The Call Of Ktulu" "Metallica" "1" "1" >/dev/null 2>&1
        sleep 0.3
        grep -c '^ARTIST=' "$tmpdir/oggenc.args"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "2" ]]
}

test_maybe_start_recording_waits_for_full_metadata_burst () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        start_recording () { printf '%s|%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5" "$6"; return 0; }
        playbackstatus="Playing"
        # MPRIS order observed from Spotify: trackNumber is emitted AFTER
        # title, so a per-line trigger would start recording before it
        # arrives - this simulates one drained burst, decided once at the end.
        process_dbus_line "trackid -> track-x"
        process_dbus_line "album -> S&M"
        process_dbus_line "artist -> Metallica"
        process_dbus_line "discnumber -> 2"
        process_dbus_line "title -> The Ecstasy Of Gold"
        process_dbus_line "tracknumber -> 5"
        maybe_start_recording
    })"

    [[ "$out" == "Metallica|S&M|The Ecstasy Of Gold||5|2" ]]
}

test_stop_recording_cleans_up () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        record_fifo_dir="$(mktemp -d)"
        record_error_log="$(mktemp)"
        fifo_dir_before="$record_fifo_dir"
        log_before="$record_error_log"
        parec_pid=""
        encoder_pid=""
        stop_current_recording
        [[ -e "$fifo_dir_before" ]] && printf 'FIFO_LEFT '
        [[ -e "$log_before" ]] && printf 'LOG_LEFT '
        printf '%s|%s|%s' "$record_fifo_dir" "$record_error_log" "$stopping_recording"
    })"

    [[ "$out" == "||false" ]]
}

test_cancel_and_exit_exits_zero () {
    local out status
    set +e
    out="$({ source "$SCRIPT_PATH"; _cancel_and_exit; } 2>&1)"
    status=$?
    set -e

    [[ $status -eq 0 ]] || return 1
    assert_contains "$out" "Cancelled."
}

test_start_recording_routing_failure_sets_recording_failed () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        ensure_target_routed () { return 1; }
        session_output_directory="$tmpdir"
        recording_failed=false
        start_recording "Artist" "Album" "Title" "AlbumArtist" "1" "1" >/dev/null 2>&1
        printf '%s' "$recording_failed"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "true" ]]
}

test_player_profile_apply_spotify_overwrites () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        sink_app_name="x"
        player_mpris_bus="y"
        player_sink_match="z"
        player_profile_apply spotify
        printf '%s|%s|%s' "$player_profile" "$sink_app_name" "$player_mpris_bus"
        [[ "$player_sink_match" == *"spotify"* ]] && printf '|match'
    })"

    [[ "$out" == "spotify|spotify|org.mpris.MediaPlayer2.spotify|match" ]]
}

test_player_profile_custom_preserves_fields () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        sink_app_name="foobar"
        player_mpris_bus="org.mpris.MediaPlayer2.foobar"
        player_sink_match="foobar*"
        player_profile_apply custom
        printf '%s|%s|%s|%s' "$player_profile" "$sink_app_name" "$player_mpris_bus" "$player_sink_match"
    })"

    [[ "$out" == "custom|foobar|org.mpris.MediaPlayer2.foobar|foobar*" ]]
}

test_status_output_relpath () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        session_output_directory="/m/sess"
        tui_output="/m/sess/Artist/Album/Track.m4a"
        status_output_relpath
        printf '|'
        tui_output="-"
        status_output_relpath
        printf '|'
        session_output_directory="/other"
        tui_output="/m/sess/x.m4a"
        status_output_relpath
    })"

    [[ "$out" == "Artist/Album/Track.m4a|-|/m/sess/x.m4a" ]]
}

test_cfg_edit_detection_input_flips_to_custom () {
    local out cfg
    cfg="$(mktemp)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        render_page () { :; }
        # shellcheck disable=SC2317
        ui_cancel_hint () { :; }
        # shellcheck disable=SC2317
        gum () { case "$1" in input) printf 'myplayer' ;; *) : ;; esac; }
        config_path="$cfg"
        player_profile="spotify"
        _cfg_edit_detection_input sink_app_name "sink_app_name"
        printf '%s|%s' "$player_profile" "$sink_app_name"
    })"
    rm -f "$cfg"

    [[ "$out" == "custom|myplayer" ]]
}

test_is_target_sink_app_profile_driven () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        player_sink_match="acme acme*"
        sink_app_name=""
        is_target_sink_app "" "acme-9" && printf 'acme-yes '
        is_target_sink_app "" "spotify" || printf 'spotify-no'
    })"

    [[ "$out" == "acme-yes spotify-no" ]]
}

test_invalid_player_profile_rejected () {
    local rc
    rc="$({
        source "$SCRIPT_PATH"
        player_profile="bogus"
        validate_settings_soft >/dev/null 2>&1
        printf '%s' "$?"
    })"

    [[ "$rc" != "0" ]]
}

# Counts every persisted key rather than naming a handful, so it catches ANY
# key silently dropped from save_config's heredoc, not just a chosen few.
test_save_config_persists_all_fields () {
    local out cfg
    cfg="$(mktemp)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        player_profile="custom"
        sink_app_name="foo"
        player_mpris_bus="org.mpris.MediaPlayer2.foo"
        player_sink_match="foo*"
        log_directory="/custom/logs"
        save_config
        grep -c -E '^[a-z_]+="' "$cfg"
    })"
    rm -f "$cfg"

    [[ "$out" == "13" ]]
}

test_effective_log_directory_default_and_override () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        log_directory=""
        effective_log_directory
        printf '|'
        log_directory="/custom/logs"
        effective_log_directory
    })"

    [[ "$out" == "${TMPDIR:-/tmp}/loopcatcher|/custom/logs" ]]
}

test_init_session_log_respects_log_directory () {
    local out base
    base="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=1
        log_directory="$base/custom-logs"
        session_name="mysession"
        init_session_log
        printf '%s' "$session_log_path"
    })"
    rm -rf "$base"

    [[ "$out" == "$base/custom-logs/mysession.log" ]]
}

test_log_level_0_writes_no_log_at_all () {
    local out base
    base="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=0
        log_directory="$base/logs"
        session_name="mysession"
        init_session_log
        log_line "should not be written"
        printf 'path=[%s]' "$session_log_path"
        [[ -d "$base/logs" ]] && printf ' DIR_EXISTS'
    })"
    rm -rf "$base"

    [[ "$out" == "path=[]" ]]
}

test_log_debug_gated_by_log_level () {
    local out base
    base="$(mktemp -d)"
    out="$({
        source "$SCRIPT_PATH"
        log_directory="$base"
        session_name="mysession"

        log_level=1
        init_session_log
        log_debug "should not appear"
        [[ -s "$session_log_path" ]] && printf 'level1-wrote ' || printf 'level1-empty '

        log_level=2
        log_debug "should appear"
        grep -c 'DEBUG: should appear' "$session_log_path"
    })"
    rm -rf "$base"

    [[ "$out" == "level1-empty 1" ]]
}

test_stop_current_recording_logs_duration_with_track_and_disc () {
    local out base
    base="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=1
        log_directory="$base"
        session_name="mysession"
        init_session_log
        record_start_seconds=$((SECONDS - 3))
        record_log_artist="Metallica"
        record_log_album="S&M"
        record_log_title="The Call Of Ktulu"
        record_log_tracknumber="2"
        record_log_discnumber="1"
        record_log_file="/x/The Call Of Ktulu.m4a"
        stop_current_recording
        cat "$session_log_path"
    })"
    rm -rf "$base"

    assert_contains "$out" 'artist="Metallica"' || return 1
    assert_contains "$out" 'title="The Call Of Ktulu"' || return 1
    assert_contains "$out" 'track="2"' || return 1
    assert_contains "$out" 'disc="1"' || return 1
    assert_contains "$out" 'duration_seconds="3"' || return 1
}

test_invalid_log_level_rejected () {
    local rc
    rc="$({
        source "$SCRIPT_PATH"
        log_level="3"
        validate_settings_soft >/dev/null 2>&1
        printf '%s' "$?"
    })"

    [[ "$rc" != "0" ]]
}

test_load_config_backfills_player () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
log_level="1"
record_format="aac"
bitrate="48"
filename_scheme="normal"
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s|%s' "$player_profile" "$player_mpris_bus"
    })"
    rm -f "$cfg"

    [[ "$out" == "spotify|org.mpris.MediaPlayer2.spotify" ]]
}

test_default_session_name_format () {
    local out
    out="$({ source "$SCRIPT_PATH"; default_session_name; })"

    # date +%Y%m%d-%H%M%S followed by "-loopcatcher", e.g. 20260829-153000-loopcatcher
    [[ "$out" =~ ^[0-9]{8}-[0-9]{6}-[a-z-]+$ ]]
}

test_validate_session_name_rejects_dots_and_slash () {
    local rc
    rc="$({
        source "$SCRIPT_PATH"
        validate_session_name "."   >/dev/null 2>&1 && printf 'dot-ok '
        validate_session_name ".."  >/dev/null 2>&1 && printf 'dotdot-ok '
        validate_session_name "a/b" >/dev/null 2>&1 && printf 'slash-ok '
        validate_session_name ""    >/dev/null 2>&1 && printf 'empty-ok '
        validate_session_name "my-session" >/dev/null 2>&1 || printf 'good-rejected'
        printf 'done'
    })"

    [[ "$rc" == "done" ]]
}

test_dir_not_empty () {
    local out d
    d="$(mktemp -d)"
    out="$({
        source "$SCRIPT_PATH"
        dir_not_empty "$d" && printf 'empty-yes '
        touch "$d/.hidden"
        dir_not_empty "$d" && printf 'dotfile-detected'
    })"
    rm -rf "$d"

    [[ "$out" == "dotfile-detected" ]]
}

test_player_bus_has_owner_empty_bus_is_alive () {
    local rc
    rc="$({
        source "$SCRIPT_PATH"
        player_mpris_bus=""
        player_bus_has_owner
        printf '%s' "$?"
    })"

    [[ "$rc" == "0" ]]
}

test_player_exit_ends_session_after_two_misses () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        # shellcheck disable=SC2317
        player_bus_has_owner () { return 1; }
        started_playing=true
        poll_player_liveness
        printf '%s|' "$should_exit"
        poll_player_liveness
        printf '%s|%s' "$should_exit" "$session_ended"
    })"

    [[ "$out" == "0|1|true" ]]
}

test_player_liveness_ignored_before_first_play () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        player_bus_has_owner () { return 1; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        started_playing=false
        poll_player_liveness
        poll_player_liveness
        poll_player_liveness
        printf '%s' "$should_exit"
    })"

    [[ "$out" == "0" ]]
}

test_clip_text_truncates_long_values () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        clip_text "short" 10
        printf '|'
        clip_text "0123456789ABCDEFGHIJ" 10
    })"

    [[ "$out" == "short|…BCDEFGHIJ" ]]
}

test_internal_wait_invalid_kind_returns_1 () {
    local rc
    rc="$({
        source "$SCRIPT_PATH"
        _internal_wait bogus --config /nonexistent
        printf '%s' "$?"
    })"

    [[ "$rc" == "1" ]]
}

test_internal_wait_sink_returns_once_condition_met () {
    local out cfg
    cfg="$(mktemp)"
    printf 'log_level="1"\n' > "$cfg"
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        get_target_sink_index () { return 0; }
        _internal_wait sink --config "$cfg"
        printf '%s' "$?"
    })"
    rm -f "$cfg"

    [[ "$out" == "0" ]]
}

run_test () {
    local name="$1"
    if "$name"; then
        pass "$name"
    else
        fail "$name"
    fi
}

main () {
    set -e

    run_test test_help_contains_long_options
    run_test test_invalid_format_rejected
    run_test test_invalid_scheme_rejected
    run_test test_file_path_structure_and_uniqueness
    run_test test_pause_stops_session
    run_test test_pause_before_first_play_does_not_exit
    run_test test_end_session_sets_flags
    run_test test_track_change_resets_metadata
    run_test test_get_dbusmessages_parses_int32_values
    run_test test_get_dbusmessages_parses_multiple_artist_values
    run_test test_process_dbus_line_collects_all_artist_values
    run_test test_start_recording_ogg_writes_all_artists_as_separate_fields
    run_test test_maybe_start_recording_waits_for_full_metadata_burst
    run_test test_normal_scheme_keeps_unicode
    run_test test_normal_scheme_strips_path_chars
    run_test test_stop_recording_cleans_up
    run_test test_cancel_and_exit_exits_zero
    run_test test_start_recording_routing_failure_sets_recording_failed
    run_test test_player_profile_apply_spotify_overwrites
    run_test test_player_profile_custom_preserves_fields
    run_test test_status_output_relpath
    run_test test_cfg_edit_detection_input_flips_to_custom
    run_test test_is_target_sink_app_profile_driven
    run_test test_invalid_player_profile_rejected
    run_test test_save_config_persists_all_fields
    run_test test_effective_log_directory_default_and_override
    run_test test_init_session_log_respects_log_directory
    run_test test_log_level_0_writes_no_log_at_all
    run_test test_log_debug_gated_by_log_level
    run_test test_stop_current_recording_logs_duration_with_track_and_disc
    run_test test_invalid_log_level_rejected
    run_test test_load_config_backfills_player
    run_test test_default_session_name_format
    run_test test_validate_session_name_rejects_dots_and_slash
    run_test test_dir_not_empty
    run_test test_player_bus_has_owner_empty_bus_is_alive
    run_test test_player_exit_ends_session_after_two_misses
    run_test test_player_liveness_ignored_before_first_play
    run_test test_clip_text_truncates_long_values
    run_test test_internal_wait_invalid_kind_returns_1
    run_test test_internal_wait_sink_returns_once_condition_met

    printf '\nTests: %s passed, %s failed\n' "$pass_count" "$fail_count"

    if [[ $fail_count -ne 0 ]]; then
        exit 1
    fi
}

main
