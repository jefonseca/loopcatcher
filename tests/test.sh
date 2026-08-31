#!/usr/bin/env bash

# shellcheck shell=bash

set -u

# Deterministic language regardless of the runner's own locale - most tests
# assert exact English catalog text, and the default $language ("auto")
# resolving to effective_language="en" is only guaranteed when
# detect_system_language() doesn't see a Spanish LANG/LC_ALL/LC_MESSAGES.
# Tests that need a specific language set $effective_language directly
# (skipping resolution) or $language (to exercise resolve_language() itself)
# - see individual tests for which. test_detect_system_language_from_lang_env
# and test_resolve_language_* override these explicitly, per-call, to test
# detection/resolution themselves.
export LANG=C LC_ALL=C LC_MESSAGES=C

ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
SCRIPT_PATH="$ROOT_DIR/loopcatcher"
SPOTIFY_NATIVE_PATH="$ROOT_DIR/profiles/spotify_native/profile.sh"
SPOTIFY_NATIVE_LANG_DIR="$ROOT_DIR/profiles/spotify_native/lang"

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

# Sources the main script, then the spotify_native module's own lang/ dir
# (via loopcatcher's own load_lang_dir(), same as a real run would) and
# profile.sh - the same set a real run ends up with active after
# load_config(). Used by every test that needs a player-profile function
# (get_dbusmessages, process_dbus_line, ...) without needing an interactive
# gum session to load it via load_config.
source_with_spotify_native () {
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    load_lang_dir "$SPOTIFY_NATIVE_LANG_DIR"
    # shellcheck disable=SC1090
    source "$SPOTIFY_NATIVE_PATH"
}

test_help_contains_long_options () {
    local out
    out="$($SCRIPT_PATH --help 2>&1)"

    assert_contains "$out" "--help" || return 1
    assert_contains "$out" "--version" || return 1
    assert_contains "$out" "--debug" || return 1
    assert_contains "$out" "--logname" || return 1
    # Regression guard for the CLI reduction itself - these flags are gone.
    assert_contains "$out" "--output" && return 1
    assert_contains "$out" "--session" && return 1
    return 0
}

test_file_path_structure_and_uniqueness () {
    local out1 out2
    local tmpdir
    tmpdir="$(mktemp -d)"

    # shellcheck disable=SC2034
    out1="$({ source_with_spotify_native; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "Artist" "Album" "Song" "m4a"; })"
    [[ "$out1" == *"Artist/Album/Song.m4a" ]] || return 1

    touch "$out1"

    # shellcheck disable=SC2034
    out2="$({ source_with_spotify_native; session_output_directory="$tmpdir"; filename_scheme="normal"; file_path_structure "Artist" "Album" "Song" "m4a"; })"
    [[ "$out2" == *"Artist/Album/Song_2.m4a" ]] || return 1

    rm -rf "$tmpdir"
}

test_pause_stops_session () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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

test_list_profile_modules_finds_spotify_native () {
    local out
    out="$({ source "$SCRIPT_PATH"; list_profile_modules; })"

    assert_contains "$out" "spotify_native"
}

test_load_config_falls_back_to_spotify_native_when_invalid () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
log_level="1"
default_profile="bogus_module"
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s' "$default_profile"
    })"
    rm -f "$cfg"

    [[ "$out" == "spotify_native" ]]
}

test_load_config_seeds_missing_profile_section () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
log_level="1"
default_profile="spotify_native"
enabled_profiles="spotify_native"
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s|%s|' "$spotify_native_sink_app_name" "$sink_app_name"
        grep -c '^spotify_native_' "$cfg"
    })"
    rm -f "$cfg"

    [[ "$out" == "spotify|spotify|3" ]]
}

test_save_config_preserves_inactive_module_lines () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
log_level="1"
default_profile="spotify_native"
enabled_profiles="spotify_native"
some_other_module_setting="kept"
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        save_config
        grep -c '^some_other_module_setting="kept"$' "$cfg"
    })"
    rm -f "$cfg"

    [[ "$out" == "1" ]]
}

test_enabled_profiles_always_includes_default_profile () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
default_profile="spotify_native"
enabled_profiles=""
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s' "$enabled_profiles"
    })"
    rm -f "$cfg"

    assert_contains "$out" "spotify_native"
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

test_invalid_default_profile_rejected () {
    local rc cfg
    cfg="$(mktemp)"
    rc="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        default_profile="bogus"
        enabled_profiles="spotify_native"
        validate_settings_soft >/dev/null 2>&1
        printf '%s' "$?"
    })"
    rm -f "$cfg"

    [[ "$rc" != "0" ]]
}

# Counts every persisted generic + active-module key rather than naming a
# handful, so it catches ANY key silently dropped from save_config.
test_save_config_persists_all_fields () {
    local out cfg
    cfg="$(mktemp)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        log_file_path="/custom/logs/x.log"
        save_config
        grep -c -E '^[a-z_]+="' "$cfg"
    })"
    rm -f "$cfg"

    # 12 fixed generic keys (including language) + 3 spotify_native_* module keys.
    [[ "$out" == "15" ]]
}

test_effective_log_file_path_default_and_override () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        log_file_path=""
        session_name="mysession"
        effective_log_file_path
        printf '|'
        log_file_path="/custom/logs/x.log"
        effective_log_file_path
    })"

    [[ "$out" == "${TMPDIR:-/tmp}/loopcatcher/mysession.log|/custom/logs/x.log" ]]
}

test_init_session_log_respects_log_file_path () {
    local out base
    base="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=1
        log_file_path="$base/custom-logs/mysession.log"
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
        log_file_path="$base/logs/mysession.log"
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
        log_file_path="$base/session.log"
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
        log_file_path="$base/session.log"
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
    local rc cfg
    cfg="$(mktemp)"
    rc="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        log_level="3"
        validate_settings_soft >/dev/null 2>&1
        printf '%s' "$?"
    })"
    rm -f "$cfg"

    [[ "$rc" != "0" ]]
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        source_with_spotify_native
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
        _internal_wait bogus --config /nonexistent 2>/dev/null
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

test_logname_sets_log_file_path () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        get_options --logname /custom/logs/x.log
        printf '%s' "$log_file_path"
    })"

    [[ "$out" == "/custom/logs/x.log" ]]
}

test_t_returns_english_by_default () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        effective_language="en"
        t ui.cancelled
    })"

    [[ "$out" == "Cancelled." ]]
}

test_t_returns_spanish_when_language_is_es () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        effective_language="es"
        load_lang_dir "$(lang_root)"
        t ui.cancelled
    })"

    [[ "$out" == "Cancelado." ]]
}

test_t_falls_back_to_english_for_missing_spanish_translation () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        effective_language="es"
        load_lang_dir "$(lang_root)"
        MSG_en[test.only_in_english]="only in english"
        t test.only_in_english
    })"

    [[ "$out" == "only in english" ]]
}

# Regression guard: t() must never crash (the "invalid arithmetic operator"
# bug hit during development) when $effective_language names a catalog that
# was never actually loaded - a corrupted/partial install missing
# lang/es.sh, or a config file persisting a language whose file didn't load
# this run. Falls back to English rather than erroring.
test_t_gracefully_falls_back_when_language_catalog_never_loaded () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        effective_language="es"
        # Deliberately no load_lang_dir call here.
        t ui.cancelled
    })"

    [[ "$out" == "Cancelled." ]]
}

test_t_returns_id_for_unknown_message () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        effective_language="en"
        t some.bogus.id.that.does.not.exist
    })"

    [[ "$out" == "some.bogus.id.that.does.not.exist" ]]
}

# "auto" is the only value that ever re-detects - an explicit "en"/"es" must
# win over the system locale even if they disagree, so switching back to
# "auto" later is the only way to follow the locale again (the whole point
# of a distinct "auto" value instead of always resolving language eagerly).
test_resolve_language_auto_follows_system_locale () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        language="auto"
        LANG="es_ES.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language 2>/dev/null
    })"

    [[ "$out" == "es" ]]
}

test_resolve_language_explicit_value_overrides_system_locale () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        language="es"
        LANG="en_US.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language
    })"

    [[ "$out" == "es" ]]
}

test_invalid_language_rejected () {
    local rc cfg
    cfg="$(mktemp)"
    rc="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        language="fr"
        validate_settings_soft >/dev/null 2>&1
        printf '%s' "$?"
    })"
    rm -f "$cfg"

    [[ "$rc" != "0" ]]
}

test_detect_system_language_from_lang_env () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        LANG="es_ES.UTF-8" LC_ALL="" LC_MESSAGES="" detect_system_language 2>/dev/null
        printf '|'
        LANG="fr_FR.UTF-8" LC_ALL="" LC_MESSAGES="" detect_system_language 2>/dev/null
    })"

    [[ "$out" == "es|en" ]]
}

# Regression guard for this phase's core design rule: editing a Settings
# field must never call load_config() again mid-session. Appends a sentinel
# entry to "enabled_profiles" after the one real load_config() call (still
# contains "spotify_native", so validate_settings_soft still passes and the
# edit below can't get stuck re-prompting), then asserts it survives an
# unrelated field edit unchanged - a reload would overwrite it back to
# whatever's actually in the file.
test_cfg_edit_input_does_not_reload_other_state () {
    local out cfg
    cfg="$(mktemp)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        render_page () { :; }
        # shellcheck disable=SC2317
        gum () { case "$1" in input) printf 'newvalue' ;; *) : ;; esac; }
        config_path="$cfg"
        load_config
        enabled_profiles="spotify_native zz_sentinel_extra"
        _cfg_edit_input nulloutput_name "prompt"
        printf '%s|%s' "$nulloutput_name" "$enabled_profiles"
    })"
    rm -f "$cfg"

    [[ "$out" == "newvalue|spotify_native zz_sentinel_extra" ]]
}

# config_changed gates whether Welcome offers "Apply configuration change" -
# must stay false after load_config()'s own automatic first-run module
# seeding (not a user edit), and flip true on a real field edit.
test_cfg_edit_input_sets_config_changed () {
    local out cfg
    cfg="$(mktemp)"
    out="$({
        source "$SCRIPT_PATH"
        # shellcheck disable=SC2317
        render_page () { :; }
        # shellcheck disable=SC2317
        gum () { case "$1" in input) printf 'newvalue' ;; *) : ;; esac; }
        config_path="$cfg"
        load_config
        printf '%s|' "$config_changed"
        _cfg_edit_input nulloutput_name "prompt"
        printf '%s' "$config_changed"
    })"
    rm -f "$cfg"

    [[ "$out" == "false|true" ]]
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
    run_test test_list_profile_modules_finds_spotify_native
    run_test test_load_config_falls_back_to_spotify_native_when_invalid
    run_test test_load_config_seeds_missing_profile_section
    run_test test_save_config_preserves_inactive_module_lines
    run_test test_enabled_profiles_always_includes_default_profile
    run_test test_status_output_relpath
    run_test test_is_target_sink_app_profile_driven
    run_test test_invalid_default_profile_rejected
    run_test test_save_config_persists_all_fields
    run_test test_effective_log_file_path_default_and_override
    run_test test_init_session_log_respects_log_file_path
    run_test test_log_level_0_writes_no_log_at_all
    run_test test_log_debug_gated_by_log_level
    run_test test_stop_current_recording_logs_duration_with_track_and_disc
    run_test test_invalid_log_level_rejected
    run_test test_default_session_name_format
    run_test test_validate_session_name_rejects_dots_and_slash
    run_test test_dir_not_empty
    run_test test_player_bus_has_owner_empty_bus_is_alive
    run_test test_player_exit_ends_session_after_two_misses
    run_test test_player_liveness_ignored_before_first_play
    run_test test_clip_text_truncates_long_values
    run_test test_internal_wait_invalid_kind_returns_1
    run_test test_internal_wait_sink_returns_once_condition_met
    run_test test_logname_sets_log_file_path
    run_test test_t_returns_english_by_default
    run_test test_t_returns_spanish_when_language_is_es
    run_test test_t_falls_back_to_english_for_missing_spanish_translation
    run_test test_t_gracefully_falls_back_when_language_catalog_never_loaded
    run_test test_t_returns_id_for_unknown_message
    run_test test_resolve_language_auto_follows_system_locale
    run_test test_resolve_language_explicit_value_overrides_system_locale
    run_test test_invalid_language_rejected
    run_test test_detect_system_language_from_lang_env
    run_test test_cfg_edit_input_does_not_reload_other_state
    run_test test_cfg_edit_input_sets_config_changed

    printf '\nTests: %s passed, %s failed\n' "$pass_count" "$fail_count"

    if [[ $fail_count -ne 0 ]]; then
        exit 1
    fi
}

main
