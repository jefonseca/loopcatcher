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
    out="$($SCRIPT_PATH --format mp3 --no-intro 2>&1)"
    local status=$?
    set -e

    [[ $status -ne 0 ]] || return 1
    assert_contains "$out" "Invalid --format value"
}

test_invalid_scheme_rejected () {
    local out
    set +e
    out="$($SCRIPT_PATH --scheme bad --no-intro 2>&1)"
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
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        status_active=false
        started_playing=true
        playbackstatus="Playing"
        process_dbus_line "playbackstatus -> Paused"
        printf '%s|%s' "$should_exit" "$tui_state"
    })"

    [[ "$out" == "1|session-ended" ]]
}

test_pause_before_first_play_does_not_exit () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        status_active=false
        started_playing=false
        process_dbus_line "playbackstatus -> Paused"
        printf '%s' "$should_exit"
    })"

    [[ "$out" == "0" ]]
}

test_finish_session_auto_exits () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        status_active=false
        started_playing=true
        playbackstatus="Playing"
        process_dbus_line "playbackstatus -> Stopped"
        printf '%s|%s' "$should_exit" "$tui_state"
    })"

    [[ "$out" == "1|session-ended" ]]
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
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        status_active=false
        title="Old Title"
        artist="Old Artist"
        album="Old Album"
        last_trackid="track-old"
        playbackstatus="Playing"
        process_dbus_line "trackid -> track-new"
        printf '%s|%s|%s|%s' "$title" "$artist" "$album" "$active_recording_signature"
    })"

    [[ "$out" == "|||" ]]
}

test_stop_recording_cleans_up () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
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

test_menu_quit_requests_exit () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        gum () { :; }
        # shellcheck disable=SC2317
        status_render () { :; }
        should_exit=0
        menu_action "Quit"
        printf '%s' "$should_exit"
    })"

    [[ "$out" == "1" ]]
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

test_config_player_edit_flips_to_custom () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        ui_screen () { :; }
        # shellcheck disable=SC2317
        gum () { case "$1" in input) printf 'myplayer' ;; *) : ;; esac; }
        player_profile="spotify"
        _cfg_edit_input sink_app_name "sink_app_name" && player_profile="custom"
        printf '%s|%s' "$player_profile" "$sink_app_name"
    })"

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

test_save_config_persists_player_fields () {
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
        save_config
        grep -c -E '^(player_profile|sink_app_name|player_mpris_bus|player_sink_match)=' "$cfg"
    })"
    rm -f "$cfg"

    [[ "$out" == "4" ]]
}

test_load_config_backfills_player () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
debug="false"
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
    run_test test_finish_session_auto_exits
    run_test test_track_change_resets_metadata
    run_test test_normal_scheme_keeps_unicode
    run_test test_normal_scheme_strips_path_chars
    run_test test_stop_recording_cleans_up
    run_test test_menu_quit_requests_exit
    run_test test_player_profile_apply_spotify_overwrites
    run_test test_player_profile_custom_preserves_fields
    run_test test_status_output_relpath
    run_test test_config_player_edit_flips_to_custom
    run_test test_is_target_sink_app_profile_driven
    run_test test_invalid_player_profile_rejected
    run_test test_save_config_persists_player_fields
    run_test test_load_config_backfills_player
    run_test test_default_session_name_format
    run_test test_validate_session_name_rejects_dots_and_slash
    run_test test_dir_not_empty

    printf '\nTests: %s passed, %s failed\n' "$pass_count" "$fail_count"

    if [[ $fail_count -ne 0 ]]; then
        exit 1
    fi
}

main
