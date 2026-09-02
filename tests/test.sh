#!/usr/bin/env bash

# shellcheck shell=bash

set -u

# Deterministic language regardless of the runner's own locale - most tests
# assert exact English catalog text, and the default $language ("auto")
# resolving to effective_language="en" is only guaranteed when
# detect_system_language() doesn't see a Spanish LANG/LC_ALL/LC_MESSAGES.
# Tests that need a specific language set $effective_language directly
# (skipping resolution) or $language (to exercise resolve_language() itself),
# and test_language_resolution_and_detection overrides the locale per call to
# exercise detection itself.
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

# A Metadata burst is one event whose key order the MPRIS dict does not
# guarantee. Reacting to a track change per LINE meant a trackid arriving
# after title/artist wiped the fields that same burst had just delivered, and
# the track recorded with no metadata - intermittently, because the order
# varies. The reset is taken once per burst now, so every order must work,
# and a genuine track change must still clear the previous track's fields.
test_track_change_is_decided_per_burst_not_per_line () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source_with_spotify_native
        # shellcheck disable=SC2317
        stop_current_recording () { :; }
        apply () {
            _apply_track_change "$@"
            local l
            for l in "$@"; do process_dbus_line "$l"; done
            printf '%s/%s ' "${artist:--}" "${title:--}"
        }
        apply "trackid -> /t/1" "title -> One" "artist -> A"      # trackid first
        apply "title -> Two" "artist -> B" "trackid -> /t/2"      # trackid last
        apply "title -> Three" "trackid -> /t/3" "artist -> C"    # trackid middle
        # a new track whose burst carries no metadata must NOT inherit C/Three
        apply "trackid -> /t/4"
    })"

    [[ "$out" == "A/One B/Two C/Three -/- " ]]
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

# Metadata with no ASCII alphanumerics at all (a CJK artist name) sanitizes
# away to nothing under the strict schemes. That used to collapse the whole
# path - "Artist/Album/Title.m4a" became "//.m4a", a single nameless hidden
# file at the session root that every track of the session then collided on.
test_strict_schemes_fall_back_when_metadata_has_no_ascii () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        session_output_directory="$tmpdir"
        filename_scheme="strict"
        strict="$(file_path_structure "日本語バンド" "アルバム" "曲名" "m4a")"
        filename_scheme="strict-lc-nodir"
        nodir="$(file_path_structure "日本語バンド" "アルバム" "曲名" "m4a")"
        printf '%s|%s' "${strict#"$tmpdir"}" "${nodir#"$tmpdir"}"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "/Unknown/Unknown/Unknown.m4a|/unknown_unknown_unknown.m4a" ]]
}

# Names Linux accepts but Windows/macOS/FAT do not: over-long components, and
# the DOS device names. One assertion covering the cap, the word-boundary cut,
# the trailing-punctuation trim, the reserved-name escape, and that an
# ordinary name is passed through untouched.
test_portable_component_caps_length_and_reserved_names () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        long="Greatest Show on Earth_ 30 Circus Songs Including Entry of the Gladiators, Barnum and Bailey's Favorite, Those Magnificent Men in Their Flying Machines, And Ringling Brothers Grand Entry!"
        capped="$(_portable_component "$long")"
        printf '%s|%s|%s|%s|%s' \
            "$(( ${#capped} <= FILENAME_COMPONENT_MAX ? 1 : 0 ))" \
            "$(( ${#capped} >= 60 ? 1 : 0 ))" \
            "${capped: -1}" \
            "$(_portable_component "NUL")" \
            "$(_portable_component "Ordinary Album")"
    })"

    # capped, not over-trimmed, no trailing space/punctuation, NUL escaped,
    # an ordinary name left exactly as it was.
    [[ "$out" == "1|1|s|NUL_|Ordinary Album" ]]
}

# ext4/APFS cap a component at 255 BYTES, so the character cap alone is not
# enough: 100 characters of CJK is over 300 bytes and the filesystem itself
# would reject the name.
test_portable_component_respects_byte_limit () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        s=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do s+="日本語のとても長いアルバム名"; done
        capped="$(_portable_component "$s")"
        printf '%s|%s' \
            "$(( $(_component_bytes "$capped") <= FILENAME_COMPONENT_MAX_BYTES ? 1 : 0 ))" \
            "$(( ${#capped} > 0 ? 1 : 0 ))"
    })"

    [[ "$out" == "1|1" ]]
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
        # the reset belongs to the burst, not to the line that carries the id
        _apply_track_change "trackid -> track-new"
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

test_list_profile_modules_finds_shipped_modules () {
    local out
    out="$({ source "$SCRIPT_PATH"; list_profile_modules; })"

    assert_contains "$out" "spotify_native"
}

# The module carrying a DEFAULT marker file is what a fresh install - or a
# config naming a module that is not installed - lands on. No module name is
# hardcoded in the main script, so this asserts the marker actually drives it.
test_default_profile_fallback_prefers_marked_module () {
    local out marked
    marked="$(cd "$ROOT_DIR" && grep -l . profiles/*/DEFAULT 2>/dev/null | head -1 | cut -d/ -f2)"
    out="$({ source "$SCRIPT_PATH"; _default_profile_fallback; })"

    [[ -n "$marked" ]] || return 1
    [[ "$out" == "$marked" ]]
}

test_load_config_falls_back_to_default_marked_module_when_invalid () {
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

# A fresh config (no enabled_profiles yet) enables every installed module, so
# Change Profile is usable without a trip to Settings first.
test_load_config_enables_all_modules_on_fresh_config () {
    local out cfg
    cfg="$(mktemp)"
    rm -f "$cfg"
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

# load_config seeds a module's whole prefixed config section the first time
# that module becomes default_profile, and profile_activate aliases it into
# the generic runtime vars. Run for BOTH shipped modules, with the expected
# key count derived from each module's own schema instead of hardcoded, so
# adding a field to either one cannot rot this test.
# The two capture modes live in one module now, chosen by this setting: "yes"
# (the default) has loopcatcher launch and drive Spotify, "no" attaches to a
# Spotify the user drives. Merging them removed 211 lines of byte-for-byte
# duplicate machinery, so this checks the flag really does select the flow.
test_manage_player_flag_selects_the_capture_mode () {
    local out cfg
    cfg="$(mktemp)"; rm -f "$cfg"
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        # default, plus both branches actually being defined and reachable
        printf '%s:%s:%s:%s' \
            "$spotify_native_manage_player" \
            "$(declare -F _run_managed >/dev/null && echo 1 || echo 0)" \
            "$(declare -F _run_attached >/dev/null && echo 1 || echo 0)" \
            "$(_profile_schema_keys | grep -c '^spotify_native_manage_player$')"
    })"
    rm -f "$cfg"

    [[ "$out" == "yes:1:1:1" ]]
}

test_load_config_seeds_the_modules_config_section () {
    local out cfg
    cfg="$(mktemp)"
    printf 'default_profile="spotify_native"\nenabled_profiles="spotify_native"\n' > "$cfg"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        # every schema key persisted, and profile_activate aliased it into the
        # generic runtime var - count derived from the schema, never hardcoded
        printf '%s:%s' \
            "$(( $(grep -c '^spotify_native_' "$cfg") == $(_profile_schema_keys | wc -l) ? 1 : 0 ))" \
            "$sink_app_name"
    })"
    rm -f "$cfg"

    [[ "$out" == "1:spotify" ]]
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

# An installed default_profile left out of enabled_profiles (hand-edited
# config) must be KEPT and re-added to the list - not silently swapped for
# whichever module happens to be the fallback.
test_enabled_profiles_always_includes_default_profile () {
    local out cfg
    cfg="$(mktemp)"
    cat > "$cfg" <<'EOF'
default_profile="spotify_native"
enabled_profiles="some_other_module"
EOF
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s|%s' "$default_profile" "$enabled_profiles"
    })"
    rm -f "$cfg"

    [[ "$out" == "spotify_native|some_other_module spotify_native" ]]
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

# Counts every persisted generic + active-module key rather than naming a
# handful, so it catches ANY key silently dropped from save_config.
# _validate_settings guards eight fields and one bad value in any of them has
# to make it fail. One test walking every branch, rather than a near-identical
# test per field - which also covers the five branches (record_format,
# filename_scheme, bitrate, aac_profile, tail_drain_seconds) that had none.
test_validate_settings_rejects_every_invalid_field () {
    local out cfg
    cfg="$(mktemp)"
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config

        # Prints only when a bad value is WRONGLY accepted, so a healthy run
        # says nothing but "done".
        _expect_rejected () {
            local field="$1" bad="$2"
            local saved="${!field}"   # separate 'local': $field is not set yet above
            printf -v "$field" '%s' "$bad"
            validate_settings_soft >/dev/null 2>&1 && printf 'ACCEPTED:%s ' "$field"
            printf -v "$field" '%s' "$saved"
        }

        # A baseline that is already invalid would make every check below pass
        # for the wrong reason.
        validate_settings_soft >/dev/null 2>&1 || printf 'BASELINE-INVALID '
        _expect_rejected record_format      "flac"
        _expect_rejected filename_scheme    "fancy"
        _expect_rejected default_profile    "bogus_module"
        _expect_rejected bitrate            "0"
        _expect_rejected aac_profile        "abc"
        _expect_rejected tail_drain_seconds "1.2.3"
        _expect_rejected log_level          "3"
        _expect_rejected language           "fr"
        printf 'done'
    })"
    rm -f "$cfg"

    [[ "$out" == "done" ]]
}

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
        # Written vs expected: every fixed generic key plus every schema key
        # of whichever module is active. Derived, not hardcoded, so adding a
        # config field or changing the default module cannot silently rot it.
        printf '%s|%s' \
            "$(grep -c -E '^[a-z_]+="' "$cfg")" \
            "$(( $(_fixed_config_keys | wc -l) + $(_profile_schema_keys | wc -l) ))"
    })"
    rm -f "$cfg"

    [[ -n "$out" && "${out%|*}" == "${out#*|}" ]]
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

test_parse_spotify_url_extracts_type_and_id () {
    local out
    out="$({
        source_with_spotify_native
        printf 'track=%s|' "$(parse_spotify_url 'https://open.spotify.com/track/2aOOFE9SV6BV0McXvnmf4n?si=8b64d25d27124212')"
        printf 'album=%s|' "$(parse_spotify_url 'https://open.spotify.com/album/0eRXMxgNfJ33uykapOFtZp?si=TRJthGowS-qAPRhjwylTyw')"
        printf 'playlist=%s|' "$(parse_spotify_url 'https://open.spotify.com/playlist/4IcpmVqgOWX1EbS6U8AJ66?si=cf3eeb617b5d4b18')"
        printf 'intl=%s|' "$(parse_spotify_url 'https://open.spotify.com/intl-es/track/2aOOFE9SV6BV0McXvnmf4n')"
        parse_spotify_url 'https://example.com/not/spotify' && printf 'invalid=matched' || printf 'invalid=rejected'
    })"

    [[ "$out" == "track=spotify:track:2aOOFE9SV6BV0McXvnmf4n|album=spotify:album:0eRXMxgNfJ33uykapOFtZp|playlist=spotify:playlist:4IcpmVqgOWX1EbS6U8AJ66|intl=spotify:track:2aOOFE9SV6BV0McXvnmf4n|invalid=rejected" ]]
}

test_profile_cleanup_kills_native_process () {
    local rc
    rc="$({
        source_with_spotify_native
        sleep 100 &
        managed_install_type="native"
        managed_pid=$!
        managed_launched=true
        profile_cleanup
        sleep 0.2
        kill -0 "$managed_pid" 2>/dev/null
        printf '%s' "$?"
    })"

    [[ "$rc" == "1" ]]
}

# Regression guard: the "Spotify is already running, close it yourself" exit
# path knows the install type but never launched anything, so cleanup must
# leave the user's own instance alone instead of closing it behind their back.
test_profile_cleanup_leaves_unlaunched_spotify_alone () {
    local rc
    rc="$({
        source_with_spotify_native
        sleep 100 &
        managed_install_type="native"
        managed_pid=$!
        managed_launched=false
        profile_cleanup
        sleep 0.2
        kill -0 "$managed_pid" 2>/dev/null
        printf '%s' "$?"
        kill "$managed_pid" 2>/dev/null
    })"

    [[ "$rc" == "0" ]]
}

test_trigger_playback_retries_before_success () {
    local out
    out="$({
        source_with_spotify_native
        # shellcheck disable=SC2317
        sleep () { :; }
        attempts=0
        # shellcheck disable=SC2317
        dbus-send () { attempts=$((attempts + 1)); [[ $attempts -ge 3 ]]; }
        player_mpris_bus="org.mpris.MediaPlayer2.spotify"
        managed_spotify_uri="spotify:track:abc"
        trigger_playback
        printf '%s|%s' "$?" "$attempts"
    })"

    [[ "$out" == "0|3" ]]
}

test_trigger_playback_gives_up_after_max_attempts () {
    local out
    out="$({
        source_with_spotify_native
        # shellcheck disable=SC2317
        sleep () { :; }
        attempts=0
        # shellcheck disable=SC2317
        dbus-send () { attempts=$((attempts + 1)); return 1; }
        player_mpris_bus="org.mpris.MediaPlayer2.spotify"
        managed_spotify_uri="spotify:track:abc"
        trigger_playback
        printf '%s|%s' "$?" "$attempts"
    })"

    [[ "$out" == "1|5" ]]
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

# The UI_WIDTH invariant has to survive both translation and a change to
# UI_WIDTH itself. Everything here is asserted as a RELATIONSHIP rather than a
# concrete number: hardcoding 100 is what let a UI_WIDTH change to 80 slip
# through with tables at 93, a Title Bar whose own text wrapped, and label/pad
# constants still derived from the old geometry. Needs no gum to render.
test_layout_widths_hold_in_every_language () {
    local out lang cfg
    out=""
    for lang in en es; do
        cfg="$(mktemp)"; rm -f "$cfg"
        out+="$({
            source "$SCRIPT_PATH"
            # The DECLARED minimum, before load_config resizes it for the
            # language: comparing the resized value against the cap would be
            # trivially true, since the resize clamps to that very cap.
            label_min=$UI_TABLE_LABEL_WIDTH
            config_path="$cfg"
            language="$lang"
            load_config
            hint_w="$(_cancel_hint_width)"
            title="LoopCatcher v$SCRIPT_VERSION - $(t spotify_native.title)"
            printf '%s%s%s%s%s ' \
                "$(( (UI_WIDTH - 4 - hint_w) + 2 + hint_w + 2 == UI_WIDTH ? 1 : 0 ))" \
                "$(( UI_TABLE_LABEL_WIDTH + (UI_WIDTH - UI_TABLE_LABEL_WIDTH - 7) + 7 == UI_WIDTH ? 1 : 0 ))" \
                "$(( $(_text_width "$(t ui.cancel_hint)") + 2 * UI_HINT_PAD <= hint_w ? 1 : 0 ))" \
                "$(( label_min <= UI_TABLE_LABEL_MAX ? 1 : 0 ))" \
                "$(( $(_text_width "$title") <= UI_WIDTH - 4 - hint_w ? 1 : 0 ))"
        })"
        rm -f "$cfg"
    done

    # title row totals UI_WIDTH | table totals UI_WIDTH | the hint fits its own
    # box | the declared label minimum is not above its cap | the Title Bar's own
    # text fits the room the hint leaves it.
    [[ "$out" == "11111 11111 " ]]
}

# ui_kv_lines pads by measured character width instead of printf's "%-*s",
# which counts BYTES under a C locale: Spanish's "Nombre de Sesión" is 16
# characters but 17 bytes, which silently misaligned its value by one column.
# All three values must therefore start at the same column.
test_ui_kv_lines_aligns_values_across_accented_labels () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        widths=""
        # "|| [[ -n $line ]]": ui_kv_lines deliberately emits no trailing
        # newline (one would render as a blank line inside the box), and a
        # plain "read" drops that last unterminated line.
        while IFS= read -r line || [[ -n "$line" ]]; do
            # everything up to the value = label, colon and its padding
            widths+="$(_text_width "${line% *}") "
        done < <(ui_kv_lines "Carpeta de Salida" "A" "Nombre de Sesión" "B" "Estado de Captura" "C")
        printf '%s' "$widths"
    })"

    [[ "$out" == "18 18 18 " ]]
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

# Regression guard for this phase's core design rule: editing a Settings
# field must never call load_config() again mid-session. Appends a sentinel
# entry to "enabled_profiles" after the one real load_config() call (still
# contains "spotify_native", so validate_settings_soft still passes and the
# edit below can't get stuck re-prompting), then asserts it survives an
# unrelated field edit unchanged - a reload would overwrite it back to
# whatever's actually in the file.
# resolve_language()'s two branches plus the detection underneath them:
# "auto" re-reads the system locale live (and anything that is not Spanish
# falls back to English), while an explicit value wins over the locale in
# either direction.
test_language_resolution_and_detection () {
    local out
    out="$({
        source "$SCRIPT_PATH"
        language="auto"; printf '%s|' "$(LANG="es_ES.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language 2>/dev/null)"
        language="auto"; printf '%s|' "$(LANG="fr_FR.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language 2>/dev/null)"
        language="es";   printf '%s|' "$(LANG="en_US.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language 2>/dev/null)"
        language="en";   printf '%s'  "$(LANG="es_ES.UTF-8" LC_ALL="" LC_MESSAGES="" resolve_language 2>/dev/null)"
    })"

    [[ "$out" == "es|en|es|en" ]]
}

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
        # Keeps default_profile in the list on purpose: _validate_settings
        # checks EVERY setting, so an edit to any field would otherwise fail
        # validation and _cfg_edit_input would re-prompt forever against a
        # stub that always answers the same thing.
        enabled_profiles="$default_profile zz_sentinel_extra"
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
    run_test test_track_change_is_decided_per_burst_not_per_line
    run_test test_pause_stops_session
    run_test test_pause_before_first_play_does_not_exit
    run_test test_end_session_sets_flags
    run_test test_track_change_resets_metadata
    run_test test_get_dbusmessages_parses_int32_values
    run_test test_get_dbusmessages_parses_multiple_artist_values
    run_test test_process_dbus_line_collects_all_artist_values
    run_test test_start_recording_ogg_writes_all_artists_as_separate_fields
    run_test test_maybe_start_recording_waits_for_full_metadata_burst
    run_test test_strict_schemes_fall_back_when_metadata_has_no_ascii
    run_test test_portable_component_caps_length_and_reserved_names
    run_test test_portable_component_respects_byte_limit
    run_test test_normal_scheme_keeps_unicode
    run_test test_normal_scheme_strips_path_chars
    run_test test_stop_recording_cleans_up
    run_test test_cancel_and_exit_exits_zero
    run_test test_start_recording_routing_failure_sets_recording_failed
    run_test test_list_profile_modules_finds_shipped_modules
    run_test test_default_profile_fallback_prefers_marked_module
    run_test test_load_config_falls_back_to_default_marked_module_when_invalid
    run_test test_load_config_enables_all_modules_on_fresh_config
    run_test test_manage_player_flag_selects_the_capture_mode
    run_test test_load_config_seeds_the_modules_config_section
    run_test test_save_config_preserves_inactive_module_lines
    run_test test_enabled_profiles_always_includes_default_profile
    run_test test_is_target_sink_app_profile_driven
    run_test test_validate_settings_rejects_every_invalid_field
    run_test test_save_config_persists_all_fields
    run_test test_effective_log_file_path_default_and_override
    run_test test_init_session_log_respects_log_file_path
    run_test test_log_level_0_writes_no_log_at_all
    run_test test_log_debug_gated_by_log_level
    run_test test_stop_current_recording_logs_duration_with_track_and_disc
    run_test test_default_session_name_format
    run_test test_validate_session_name_rejects_dots_and_slash
    run_test test_dir_not_empty
    run_test test_player_bus_has_owner_empty_bus_is_alive
    run_test test_parse_spotify_url_extracts_type_and_id
    run_test test_profile_cleanup_kills_native_process
    run_test test_profile_cleanup_leaves_unlaunched_spotify_alone
    run_test test_trigger_playback_retries_before_success
    run_test test_trigger_playback_gives_up_after_max_attempts
    run_test test_player_exit_ends_session_after_two_misses
    run_test test_player_liveness_ignored_before_first_play
    run_test test_layout_widths_hold_in_every_language
    run_test test_ui_kv_lines_aligns_values_across_accented_labels
    run_test test_clip_text_truncates_long_values
    run_test test_logname_sets_log_file_path
    run_test test_t_returns_english_by_default
    run_test test_t_returns_spanish_when_language_is_es
    run_test test_t_falls_back_to_english_for_missing_spanish_translation
    run_test test_t_gracefully_falls_back_when_language_catalog_never_loaded
    run_test test_t_returns_id_for_unknown_message
    run_test test_language_resolution_and_detection
    run_test test_cfg_edit_input_does_not_reload_other_state
    run_test test_cfg_edit_input_sets_config_changed

    printf '\nTests: %s passed, %s failed\n' "$pass_count" "$fail_count"

    if [[ $fail_count -ne 0 ]]; then
        exit 1
    fi
}

main
