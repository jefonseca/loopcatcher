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
        tui_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        started_playing=true
        playbackstatus="Playing"
        process_dbus_line "playbackstatus -> Paused"
        printf '%s|%s|%s' "$exit_on_any_key" "$tui_state" "$tui_hint"
    })"

    [[ "$out" == "true|session-ended|Press any key to exit" ]]
}

test_pause_before_first_play_does_not_exit () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        tui_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        started_playing=false
        process_dbus_line "playbackstatus -> Paused"
        printf '%s|%s' "$exit_on_any_key" "$should_exit"
    })"

    [[ "$out" == "false|0" ]]
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
        tui_render () { :; }
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
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
        tui_render () { :; }
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

test_q_key_requests_exit () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        tui_render () { :; }
        should_exit=0
        exit_on_any_key=false
        handle_keypress "q"
        printf '%s' "$should_exit"
    })"

    [[ "$out" == "1" ]]
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
    run_test test_track_change_resets_metadata
    run_test test_normal_scheme_keeps_unicode
    run_test test_normal_scheme_strips_path_chars
    run_test test_stop_recording_cleans_up
    run_test test_q_key_requests_exit

    printf '\nTests: %s passed, %s failed\n' "$pass_count" "$fail_count"

    if [[ $fail_count -ne 0 ]]; then
        exit 1
    fi
}

main
