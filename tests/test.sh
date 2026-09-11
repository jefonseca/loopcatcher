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
        filename_scheme="stream"
        nodir="$(file_path_structure "日本語バンド" "アルバム" "曲名" "m4a")"
        printf '%s|%s' "${strict#"$tmpdir"}" "${nodir#"$tmpdir"}"
    })"
    rm -rf "$tmpdir"

    # stream drops the album, so only artist+title fall back (two parts, not
    # three), behind the capture-order counter every stream name carries.
    [[ "$out" == "/Unknown/Unknown/Unknown.m4a|/0001_unknown_unknown.m4a" ]]
}

test_stream_scheme_drops_album () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    out="$({
        source "$SCRIPT_PATH"
        session_output_directory="$tmpdir"
        filename_scheme="stream"
        file_path_structure "Artist" "Album" "Song" "m4a"
    })"
    rm -rf "$tmpdir"

    # Flat, lowercased, album omitted, no artist/album subdirs, capture number
    # in front.
    [[ "$out" == "$tmpdir/0001_artist_song.m4a" ]]
}

# The whole numbering contract in one fixture: the counter starts where
# stream_start_number says, advances ONLY when a capture really started (a run
# that fails to route reuses its number instead of leaving a hole), and the
# number leads the flat name so the folder sorts back into capture order.
test_stream_scheme_numbers_files_in_capture_order () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        # Long enough to outlive start_recording's own 0.2s liveness check,
        # short enough not to hold the command substitution open: these stubs
        # inherit its stdout, so "$( )" does not close until they exit.
        # shellcheck disable=SC2317
        oggenc () { sleep 1; }
        # shellcheck disable=SC2317
        parec () { sleep 1; }
        rec_temp_dir="$tmpdir/rectmp"; mkdir -p "$rec_temp_dir"
        session_output_directory="$tmpdir"
        record_format="ogg"
        filename_scheme="stream"
        stream_start_number=501
        init_session_log

        # shellcheck disable=SC2317
        ensure_target_routed () { return 0; }
        start_recording "Artist" "Album" "First" "Artist" "1" "1" >/dev/null 2>&1
        printf '%s ' "$(basename "$record_log_file")"

        # A failed start must not consume a number.
        # shellcheck disable=SC2317
        ensure_target_routed () { return 1; }
        start_recording "Artist" "Album" "Lost" "Artist" "2" "1" >/dev/null 2>&1

        # shellcheck disable=SC2317
        ensure_target_routed () { return 0; }
        start_recording "Artist" "Album" "Second" "Artist" "3" "1" >/dev/null 2>&1
        printf '%s' "$(basename "$record_log_file")"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "0501_artist_first.oga 0502_artist_second.oga" ]]
}

# A capture session is long and unattended; the log is the only thing that can
# explain afterwards what happened, so it has to be on without being asked for.
test_default_log_level_is_1 () {
    local out
    out="$({ source "$SCRIPT_PATH"; printf '%s' "$log_level"; })"

    [[ "$out" == "1" ]]
}

test_default_filename_scheme_is_stream () {
    local out
    out="$({ source "$SCRIPT_PATH"; printf '%s' "$filename_scheme"; })"

    [[ "$out" == "stream" ]]
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

test_get_dbusmessages_preserves_embedded_quotes_in_string_values () {
    # dbus-monitor does not escape quotes inside a string value, so a field
    # split on `"` truncated a title like `Always with Me (From "Spirited
    # Away")` to `Always with Me (From`. The value must survive intact.
    local out
    # shellcheck disable=SC2034
    out="$({
        source_with_spotify_native
        # shellcheck disable=SC2317
        dbus-monitor () {
            cat <<'EOF'
   dict entry(
      string "xesam:title"
      variant             string "Always with Me (From "Spirited Away") [Piano Version]"
   )
EOF
        }
        get_dbusmessages "unused-rule"
    })"

    [[ "$out" == 'title -> Always with Me (From "Spirited Away") [Piano Version]' ]]
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

test_maybe_start_recording_queries_metadata_when_burst_missed () {
    # "Playing" arrived but no Metadata burst reached the coproc, so title and
    # artist are empty. maybe_start_recording must actively query the player
    # (dbus-send) and start from that snapshot rather than stay idle forever.
    local out
    # shellcheck disable=SC2034
    out="$({
        source_with_spotify_native
        # shellcheck disable=SC2317
        start_recording () { printf '%s|%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5" "$6"; return 0; }
        # shellcheck disable=SC2317
        dbus-send () {
            cat <<'EOF'
   variant       array [
         dict entry(
            string "mpris:trackid"
            variant                string "track-q"
         )
         dict entry(
            string "xesam:title"
            variant                string "Merry-Go-Round of Life (From "Howl's Moving Castle")"
         )
         dict entry(
            string "xesam:artist"
            variant                array [
                  string "Joe Hisaishi"
               ]
         )
      ]
EOF
        }
        playbackstatus="Playing"
        maybe_start_recording
    })"

    [[ "$out" == 'Joe Hisaishi||Merry-Go-Round of Life (From "Howl'"'"'s Moving Castle")|||' ]]
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

test_start_recording_captures_to_temp_not_final () {
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
        rec_temp_dir="$tmpdir/rectmp"; mkdir -p "$rec_temp_dir"
        session_output_directory="$tmpdir/out"
        record_format="ogg"
        start_recording "Artist" "Album" "Song" "Artist" "1" "1" >/dev/null 2>&1
        sleep 0.3
        # The encoder's -o argument is the line right after "-o".
        oarg="$(grep -A1 '^-o$' "$tmpdir/oggenc.args" | tail -1)"
        # Encoder writes to the temp file under rec_temp_dir; nothing has landed
        # at the final destination yet (the move happens only on finalize).
        [[ "$oarg" == "$record_temp_file" && "$record_temp_file" == "$rec_temp_dir"/* ]] && printf 'TEMP '
        # Nothing has landed at the final destination yet, whatever the active
        # scheme names it - checked by listing the session dir rather than
        # probing one scheme's path, which would pass vacuously under another.
        [[ -n "$(find "$session_output_directory" -type f -name '*.oga' 2>/dev/null)" ]] && printf 'FINAL_EXISTS'
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "TEMP " ]]
}

test_finalize_recording_moves_temp_to_final () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        temp="$tmpdir/rec123"; printf 'AUDIO' > "$temp"
        final="$tmpdir/out/Artist/Album/Song.oga"
        # Empty encoder PID = "already finished": moves immediately.
        _finalize_recording "" "$temp" "$final"
        printf 'final=%s|temp_gone=%s|content=%s' \
            "$([[ -f "$final" ]] && echo yes || echo no)" \
            "$([[ -e "$temp" ]] && echo no || echo yes)" \
            "$(cat "$final" 2>/dev/null)"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "final=yes|temp_gone=yes|content=AUDIO" ]]
}

test_finalize_recording_does_not_clobber_existing_final () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=0
        mkdir -p "$tmpdir/out"
        printf 'OLD' > "$tmpdir/out/Song.oga"
        temp="$tmpdir/rec123"; printf 'NEW' > "$temp"
        _finalize_recording "" "$temp" "$tmpdir/out/Song.oga"
        # The existing file is untouched; the move re-uniquifies to _2.
        printf 'orig=%s|moved=%s' \
            "$(cat "$tmpdir/out/Song.oga")" \
            "$(cat "$tmpdir/out/Song_2.oga" 2>/dev/null)"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "orig=OLD|moved=NEW" ]]
}

test_stop_current_recording_spawns_finalizer_and_clears_paths () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=0
        parec_pid=""; encoder_pid=""
        record_temp_file="$tmpdir/rec123"; printf 'AUDIO' > "$record_temp_file"
        record_log_file="$tmpdir/out/Song.oga"
        record_start_seconds=$SECONDS
        stop_current_recording
        wait "${finalizer_pids[@]}" 2>/dev/null
        # One move was queued, the in-flight paths were cleared, and the file
        # actually landed at its final destination.
        printf 'count=%s|temp=%s|log=%s|moved=%s' \
            "${#finalizer_pids[@]}" "$record_temp_file" "$record_log_file" \
            "$([[ -f "$tmpdir/out/Song.oga" ]] && echo yes || echo no)"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "count=1|temp=|log=|moved=yes" ]]
}

test_use_system_temp_no_uses_partial_recording_dir () {
    local out tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=0
        use_system_temp="no"
        session_output_directory="$tmpdir/out/mysession"
        init_session_log
        printf 'dir=%s|exists=%s' \
            "$rec_temp_dir" \
            "$([[ -d "$rec_temp_dir" ]] && echo yes || echo no)"
    })"
    rm -rf "$tmpdir"

    [[ "$out" == "dir=$tmpdir/out/mysession/partial_recording|exists=yes" ]]
}

test_use_system_temp_yes_uses_system_temp_dir () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        log_level=0
        use_system_temp="yes"
        init_session_log
        # Under the system temp loopcatcher dir, and created.
        [[ "$rec_temp_dir" == "${TMPDIR:-/tmp}/loopcatcher/"* && -d "$rec_temp_dir" ]] && printf 'SYSTEM_TEMP'
        rm -rf "$rec_temp_dir"
    })"

    [[ "$out" == "SYSTEM_TEMP" ]]
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

# The regression guard for the seeding rule. load_config used to reseed the
# WHOLE module section the moment a single schema key was missing, so the first
# launch after a module grew a field silently reset every setting the user had
# customised - manage_player included, which would have flipped an attached-mode
# user back into managed mode mid-project. Only the missing key may be filled.
test_load_config_fills_only_missing_module_keys () {
    local out cfg
    cfg="$(mktemp)"
    {
        printf 'default_profile="spotify_native"\nenabled_profiles="spotify_native"\n'
        printf 'spotify_native_manage_player="no"\n'
        printf 'spotify_native_sink_app_name="mine"\n'
        printf 'spotify_native_mpris_bus="org.example.Bus"\n'
        printf 'spotify_native_mpris_wait_timeout_seconds="42"\n'
        printf 'spotify_native_sink_match="mine mine*"\n'
    } > "$cfg"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        config_path="$cfg"
        load_config
        printf '%s:%s:%s:%s:%s' \
            "$spotify_native_manage_player" \
            "$spotify_native_sink_app_name" \
            "$spotify_native_mpris_wait_timeout_seconds" \
            "$spotify_native_stream_start_number" \
            "$(( $(grep -c '^spotify_native_' "$cfg") == $(_profile_schema_keys | wc -l) ? 1 : 0 ))"
        # A schema default is one tab-separated field, and an empty one must
        # stay empty: a tab is IFS whitespace, so reading the row with
        # "IFS=$'\t' read -r key label default" collapses a run of tabs and
        # shifts the kind into the default's place.
        profile_config_schema () {
            printf 'demo_spaced\tLabel\tspotify spotify*\tinput\n'
            printf 'demo_empty\tLabel\t\tinput\n'
        }
        _seed_missing_profile_keys demo_spaced demo_empty
        printf ':%s:%s' "$demo_spaced" "$demo_empty"
    })"
    rm -f "$cfg"

    [[ "$out" == "no:mine:42:1:1:spotify spotify*:" ]]
}

# A field a module says does not apply is hidden from the Profile Settings menu
# but stays in the schema, so it is still seeded, saved and validated. The
# filter lives in _profile_schema_rows precisely so all four parallel arrays
# shrink together - filtering when the menu is built instead would shift the
# index dispatch and edit a different field than the one selected.
test_profile_field_visible_hides_the_row_but_keeps_the_key () {
    local out
    out="$({
        source_with_spotify_native
        profile_apply_defaults
        _show () {
            spotify_native_manage_player="$1"; filename_scheme="$2"
            _profile_schema_rows
            printf '%s%s ' \
                "$(printf '%s\n' "${schema_keys[@]}" | grep -c '^spotify_native_stream_start_number$')" \
                "$(( ${#schema_keys[@]} == ${#schema_labels[@]} \
                  && ${#schema_keys[@]} == ${#schema_kinds[@]} \
                  && ${#schema_keys[@]} == ${#schema_choices[@]} ? 0 : 9 ))"
        }
        _show no stream; _show yes stream; _show no normal; _show yes normal
        # Hidden or not, save_config still persists it.
        printf '%s' "$(_profile_schema_keys | grep -c '^spotify_native_stream_start_number$')"
    })"

    [[ "$out" == "10 00 00 00 1" ]]
}

# The start number reaches printf '%04d', where bash reads a leading zero as
# octal ("0050" would number the first file 0040 and "0090" is not even valid
# octal), so profile_activate normalises it with 10# and falls back to 1 for
# anything outside 1-9999. Managed mode always starts at 1: loopcatcher opens
# the playlist itself, from the top.
test_stream_start_number_is_normalised_per_capture_mode () {
    local out
    out="$({
        source_with_spotify_native
        profile_apply_defaults
        _seed () {
            spotify_native_manage_player="$1"; spotify_native_stream_start_number="$2"
            profile_activate
            printf '%s ' "$stream_start_number"
        }
        _seed no 0050; _seed no 9999; _seed yes 50; _seed no 0; _seed no 12000; _seed no abc
        # And an out-of-range value is reported, not silently swallowed.
        spotify_native_stream_start_number="12000"
        printf '%s' "$(profile_validate_settings >/dev/null && echo accepted || echo rejected)"
    })"

    [[ "$out" == "50 9999 1 1 1 1 rejected" ]]
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

# The routing bug that recorded whole tracks as digital silence: the old
# ensure_target_routed reused a cached sink-input index and only re-detected
# when moving it failed - which it does not, when some OTHER stream has
# inherited that index. One fixture asserts the whole replacement contract:
# the stale index is never used, every stream of the player is routed (not just
# the first match), a stream already on the capture sink is left alone, another
# application's stream is never touched, and capture_route_live reports that
# audio can genuinely reach the capture sink.
# pactl's sink-input blocks put the player's OWN text under "Properties:", and
# media.name is the track title. A title like "Sink: The Movie" used to be read
# as the block's Sink field, so the routing check believed a stream it had never
# looked at. Block fields are read above Properties only. Same fixture also
# covers a stream with no application.name at all (skipped, not crashed) and
# confirms the newest match is the one reported.
test_target_sink_inputs_reads_block_fields_not_property_text () {
    local out
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        sink_app_name="spotify"
        player_sink_match="spotify spotify*"
        # shellcheck disable=SC2317
        pactl () {
            printf 'Sink Input #61\n\tSink: 3\n\tCorked: no\n\tSink Latency: 21333 usec\n\tProperties:\n'
            printf '\t\tmedia.name = "Sink: The Movie"\n\t\tapplication.process.id = "4821"\n'
            printf 'Sink Input #62\n\tSink: 3\n\tCorked: yes\n\tProperties:\n'
            printf '\t\tapplication.name = "Spotify"\n\t\tmedia.name = "Corked: no"\n'
            printf 'Sink Input #63\n\tSink: 7\n\tCorked: no\n\tProperties:\n\t\tapplication.name = "spotify"\n'
        }
        _target_sink_inputs | tr '\t' ',' | tr '\n' ' '
        get_target_sink_index && printf 'newest=%s' "$source_sink_index"
    })"

    # 61 has no application.name, so it is not ours; 62 stays corked despite a
    # track title that says otherwise; 63 keeps the sink its own field declares.
    [[ "$out" == "62,3,yes 63,7,no newest=63" ]]
}

test_routing_moves_every_player_stream_and_ignores_a_stale_index () {
    local out moves
    moves="$(mktemp)"
    # shellcheck disable=SC2034
    out="$({
        source "$SCRIPT_PATH"
        nulloutput_name="loopcatcher"
        sink_app_name="spotify"
        player_sink_match="spotify spotify*"
        source_sink_index="99"        # stale: belongs to a stream long gone
        # shellcheck disable=SC2317
        pactl () {
            case "$1 $2" in
                "list short")
                    printf '3\talsa_output.pci\tmodule-alsa-card\ts16le 2ch 48000Hz\tRUNNING\n'
                    printf '7\tloopcatcher\tmodule-null-sink\ts16le 2ch 44100Hz\tIDLE\n'
                    ;;
                "list sink-inputs")
                    printf 'Sink Input #10\n\tSink: 3\n\tCorked: no\n\tProperties:\n\t\tapplication.name = "Chromium"\n'
                    printf 'Sink Input #11\n\tSink: 3\n\tCorked: yes\n\tProperties:\n\t\tapplication.name = "spotify"\n'
                    printf 'Sink Input #12\n\tSink: 7\n\tCorked: no\n\tProperties:\n\t\tapplication.name = "Spotify"\n'
                    ;;
                "move-sink-input"*) printf 'moved=%s ' "$2" >> "$moves" ;;
            esac
            return 0
        }
        ensure_target_routed
        printf 'rc=%s index=%s live=%s ' "$?" "$source_sink_index" "$capture_route_live"
        cat "$moves"
    })"
    rm -f "$moves"

    [[ "$out" == "rc=0 index=12 live=true moved=11 " ]]
}

# The other half of the same fix: when the player's stream is NOT on the
# capture sink and cannot be moved there, parec still reads a valid,
# full-length stream of zeroes off the idle monitor - so the only way the
# session can ever know is this flag. poll_capture_route turns it into exactly
# one log line per episode, after three consecutive polls (a stream is
# legitimately corked for a moment at every track boundary).
test_capture_route_poll_logs_silence_once_per_episode () {
    local out base
    base="$(mktemp -d)"
    # shellcheck disable=SC2034
    out="$({
        source_with_spotify_native
        log_level=1
        log_file_path="$base/session.log"
        session_name="mysession"
        init_session_log
        nulloutput_name="loopcatcher"
        sink_app_name="spotify"
        player_sink_match="spotify spotify*"
        active_recording_signature="track:1"
        title="Enter Sandman"
        # shellcheck disable=SC2317
        pactl () {
            case "$1 $2" in
                "list short") printf '7\tloopcatcher\tmodule-null-sink\ts16le 2ch 44100Hz\tIDLE\n' ;;
                "list sink-inputs")
                    printf 'Sink Input #11\n\tSink: 3\n\tCorked: no\n\tProperties:\n\t\tapplication.name = "spotify"\n'
                    ;;
                "move-sink-input"*) return 1 ;;
            esac
            return 0
        }
        poll_capture_route; poll_capture_route; poll_capture_route; poll_capture_route
        printf 'warned=%s ' "$(grep -c 'capturing silence' "$session_log_path")"
        # Nothing is recording: the poll must stay out of the way entirely.
        active_recording_signature=""
        capture_silent_polls=0
        poll_capture_route
        printf 'idle=%s' "$capture_silent_polls"
    })"
    rm -rf "$base"

    [[ "$out" == "warned=1 idle=0" ]]
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
        _expect_rejected filename_scheme    "strict-lc-nodir"   # renamed to "stream"; old token no longer valid
        _expect_rejected default_profile    "bogus_module"
        _expect_rejected bitrate            "0"
        _expect_rejected aac_profile        "abc"
        _expect_rejected tail_drain_seconds "1.2.3"
        _expect_rejected log_level          "3"
        _expect_rejected use_system_temp    "maybe"
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
    run_test test_get_dbusmessages_preserves_embedded_quotes_in_string_values
    run_test test_maybe_start_recording_queries_metadata_when_burst_missed
    run_test test_get_dbusmessages_parses_multiple_artist_values
    run_test test_process_dbus_line_collects_all_artist_values
    run_test test_start_recording_ogg_writes_all_artists_as_separate_fields
    run_test test_maybe_start_recording_waits_for_full_metadata_burst
    run_test test_strict_schemes_fall_back_when_metadata_has_no_ascii
    run_test test_stream_scheme_drops_album
    run_test test_stream_scheme_numbers_files_in_capture_order
    run_test test_default_log_level_is_1
    run_test test_default_filename_scheme_is_stream
    run_test test_portable_component_caps_length_and_reserved_names
    run_test test_portable_component_respects_byte_limit
    run_test test_normal_scheme_keeps_unicode
    run_test test_normal_scheme_strips_path_chars
    run_test test_stop_recording_cleans_up
    run_test test_cancel_and_exit_exits_zero
    run_test test_start_recording_routing_failure_sets_recording_failed
    run_test test_start_recording_captures_to_temp_not_final
    run_test test_finalize_recording_moves_temp_to_final
    run_test test_finalize_recording_does_not_clobber_existing_final
    run_test test_stop_current_recording_spawns_finalizer_and_clears_paths
    run_test test_use_system_temp_no_uses_partial_recording_dir
    run_test test_use_system_temp_yes_uses_system_temp_dir
    run_test test_list_profile_modules_finds_shipped_modules
    run_test test_default_profile_fallback_prefers_marked_module
    run_test test_load_config_falls_back_to_default_marked_module_when_invalid
    run_test test_load_config_enables_all_modules_on_fresh_config
    run_test test_manage_player_flag_selects_the_capture_mode
    run_test test_load_config_seeds_the_modules_config_section
    run_test test_load_config_fills_only_missing_module_keys
    run_test test_profile_field_visible_hides_the_row_but_keeps_the_key
    run_test test_stream_start_number_is_normalised_per_capture_mode
    run_test test_save_config_preserves_inactive_module_lines
    run_test test_enabled_profiles_always_includes_default_profile
    run_test test_is_target_sink_app_profile_driven
    run_test test_target_sink_inputs_reads_block_fields_not_property_text
    run_test test_routing_moves_every_player_stream_and_ignores_a_stale_index
    run_test test_capture_route_poll_logs_silence_once_per_episode
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
