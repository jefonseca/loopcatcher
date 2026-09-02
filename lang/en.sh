# shellcheck shell=bash
###############################################################################
# lang/en.sh - main-script message catalog, English.
#
# English is the fallback baseline: t() falls back to this array whenever the
# active language's entry is missing, so EVERY message id the app ever looks
# up must exist here. Always loaded first (see load_lang_dir() in
# loopcatcher), regardless of which language is actually active - the
# selected language's own file (lang/es.sh, ...) is loaded on top of this one
# as an overlay, one file per language, so contributing or fixing a single
# language never touches this file or any other language's.
#
# Every user-facing string the FIXED part of the app prints or displays lives
# here, keyed by dotted message id and looked up at render time via t() (also
# defined in loopcatcher). Two exceptions, deliberately out of scope:
#   - log_line()/log_recording()/log_debug() entries: written to the session
#     LOG FILE, not the screen, structured/parseable, and meant to stay
#     grep-consistent across a language change - never translated.
#   - A profile module's own README.md (About Profile): the author's free-form
#     doc, shown verbatim, single-language.
#
# A profile module's own on-screen strings (Wizard step text, Recording
# screen table/field labels, ...) do NOT live here, even though screens are
# rendered with this script's generic elements - they live in that module's
# own profiles/<name>/lang/ instead (see profiles/spotify_native/lang/ for
# the shipped example), so removing a module's directory removes 100% of its
# strings with it, nothing orphaned here. load_lang_dir() merges a module's
# lang/ into these same MSG_en/MSG_es arrays once that module is loaded (see
# load_profile_module() in loopcatcher), so t() finds either kind of id the
# same way regardless of which file actually declared it.
#
# Every entry is a plain string, used either as-is ("$(t some.id)") or as a
# printf format consumed with extra args ("$(t some.id "$value")"). Keep %s
# placeholder COUNT AND ORDER identical to every other language's entry for
# the same id - t() passes the same argument list to whichever one it picks.
# A literal percent sign in an entry that takes args must be written "%%".
#
# ONE PANEL, ONE MESSAGE. Where a screen shows a block of connected text, it
# is a single MULTI-LINE entry (a plain single-quoted string spanning several
# lines), not one id per sentence - so a translator reads it, and rewrites
# it, as the connected text it actually is, and is free to re-flow, merge or
# split lines to suit their language. Two rules for those entries:
#   - DO NOT hand-wrap a sentence to fit the box. gum wraps text well, and a
#     translation that has to be re-measured and re-broken by hand every time
#     the layout or the wording moves is not maintainable. Write a sentence as
#     one line however long it is.
#   - Use a newline only where it MEANS something: one per list item, and a
#     blank line where you want a blank line on screen.
#
# The "-g" on "declare -gA" below is load-bearing, not decoration: this file
# is sourced from inside a function (load_lang_dir(), in loopcatcher) rather
# than at top level, and a plain "declare -A" inside a function creates a
# variable scoped to THAT function's call frame - even though the code lives
# in a different, sourced file - so it would vanish the moment load_lang_dir()
# returns, leaving no MSG_en for t() to read. If you're adding a new
# language's file, keep "-gA" there too.
###############################################################################

declare -gA MSG_en=(
    # --- dependency / early diagnostics ---
    [dep.missing_command]='required command "%s" was not found in PATH.'
    [dep.gum_install_hint]='Install it with: sudo apt install gum   (Debian 13+; older releases: repo.charm.sh)'
    [dep.missing_encoder]='"%s" is required for record_format=%s but was not found'
    [err.requires_tty]='%s requires an interactive terminal.'

    # --- generic UI chrome ---
    [ui.cancel_hint]='Ctrl+C to cancel'
    [ui.catching]='Catching...'
    [ui.cancelled]='Cancelled.'
    [common.back]='< Back'
    [common.press_any_key_continue]='Press any key to continue.'
    [common.table.field]='Field'
    [common.table.value]='Value'

    # --- config file ---
    [err.cannot_create_config_dir]='cannot create config directory: %s'
    [warn.config_mktemp_failed]='could not write config (mktemp failed in %s)'
    [err.invalid_record_format]='Invalid record_format: %s (allowed: aac, ogg)'
    [err.invalid_filename_scheme]='Invalid filename_scheme: %s (normal, strict, strict-lc-nodir)'
    [err.invalid_default_profile]='Invalid default_profile: %s (not installed, or not enabled)'
    [err.invalid_bitrate]='Invalid bitrate: %s (must be a positive integer)'
    [err.invalid_aac_profile]='Invalid aac_profile: %s (must be a positive integer)'
    [err.invalid_tail_drain_seconds]='Invalid tail_drain_seconds: %s (non-negative number, e.g. 0.35)'
    [err.invalid_log_level]='Invalid log_level: %s (allowed: 0, 1, 2)'
    [err.invalid_language]='Invalid language: %s (allowed: auto, en, es)'
    [err.profile_module_not_found]='profile module not found: %s (%s)'

    # --- output directory / session name ---
    [err.no_output_directory]='could not determine an output directory (HOME is unset).'
    [err.cannot_create_output_directory]='cannot create output directory: %s'
    [err.session_name_empty]='Session name cannot be empty'
    [err.session_name_dots]="Session name cannot be '.' or '..'"
    [err.session_name_slash]="Session name cannot contain '/'"
    [err.cannot_create_session_folder]='cannot create session folder: %s'
    [session.error.folder_not_empty]='Session folder exists and is not empty: %s'
    [session.intro]='This is the session name. It is used to generate the destination folder for what will be recorded, so existing files are not accidentally overwritten.'
    [session.instruction]='Enter a UNIQUE session name that has not been used before.'
    [session.input_header]='Session name (Enter for the suggested name, Esc to cancel)'
    [session.title]='Session Name'

    # --- Welcome / main menu ---
    [welcome.title]='Welcome'
    [welcome.config_heading]='Configuration'
    [welcome.field.codec]='Codec'
    [welcome.field.aac_profile]='AAC Profile'
    [welcome.field.bitrate]='Bitrate'
    [welcome.field.player_profile]='Player Profile'
    [welcome.field.output_directory]='Output Directory'
    [welcome.menu.header]='Main menu'
    [welcome.menu.continue]='Continue'
    [welcome.menu.profile]='Profile'
    [welcome.menu.settings]='Settings'
    [welcome.menu.apply_changes]='Apply configuration change'
    [welcome.menu.about]='About'
    [welcome.menu.exit]='Exit'

    # --- Profile menu ---
    [profile.title]='Profile'
    [profile.menu.header]='Profile: %s'
    [profile.menu.change]='Change Profile'
    [profile.menu.settings]='Profile Settings'
    [profile.menu.about]='About Profile'
    [profile.change.header]='Select the default profile'
    [profile.settings.header]='Profile Settings: %s'
    [profile.about.no_readme]='No README available for this profile.'

    # --- About (app-level) ---
    [about.title]='About'
    # %s is the app version. One panel, one message - see the note at the top.
    [about.body]='LoopCatcher v%s

A Linux TUI that captures desktop media player loopback audio into organized, auto-tagged audio files.

License: MIT
Homepage: https://github.com/jefonseca/loopcatcher'

    # --- Configuration / Settings ---
    [config.title]='Configuration'
    # %s is the config file path.
    [config.notify.body]='Every option below is saved automatically as soon as you change it
Changes apply once you pick "Apply configuration change" from the Welcome menu
You can also edit the config file directly:

%s'
    [config.header]='Select a group'
    [config.group.codecs]='Codecs'
    [config.group.paths]='Paths'
    [config.group.enabled_profiles]='Enabled Profiles'
    [config.group.advanced]='Advanced'
    [config.codecs.record_format]='Record Format:  %s'
    [config.codecs.aac_profile]='AAC Profile:  %s'
    [config.codecs.bitrate]='Bitrate:  %s'
    [config.codecs.record_format_prompt]='Record format'
    [config.codecs.aac_profile_prompt]='AAC profile (applies to aac only)'
    [config.codecs.bitrate_prompt]='Bitrate (kbps)'
    [config.paths.output_folder]='Output Folder:  %s'
    [config.paths.filename_scheme]='Filename Scheme:  %s'
    [config.paths.log_file]='Log File:  %s'
    [config.paths.filename_scheme_prompt]='Filename scheme'
    [config.paths.log_file_prompt]='Log file path (leave empty for the default: %s)'
    [config.enabled_profiles.header]='Enabled Profiles (default profile is always included)'
    [config.advanced.tail_drain_seconds]='Tail Drain Seconds:  %s'
    [config.advanced.log_level]='Log Level:  %s'
    [config.advanced.nulloutput_name]='Null Sink Name:  %s'
    [config.advanced.tail_drain_seconds_prompt]='Tail drain seconds (e.g. 0.35)'
    [config.advanced.log_level_prompt]='Log level (0=off, 1=on, 2=debug)'
    [config.advanced.nulloutput_name_prompt]='Null sink name'
    [config.top.language]='Language:  %s'
    [config.top.language_prompt]='Language'

    # --- Recording Wizard (generic step-screen renderer) ---
    [wizard.title]='Recording Wizard'
    [wizard.step_label]='Step %s: %s'
    [wizard.spin.sink]='Waiting for the audio sink...'
    [wizard.spin.stopped]='Waiting for playback to pause...'
    [wizard.spin.playing]='Waiting for playback to start...'
    [wizard.spin.default]='Waiting...'

    # --- Audio server / sink routing ---
    [err.audio_server_unreachable]='cannot connect to the PulseAudio/PipeWire session daemon.'
    [err.audio_server_kde_hint]='On KDE, ensure pipewire-pulse is running in your user session.'
    [err.audio_server_try_hint]='Try: systemctl --user status pipewire pipewire-pulse wireplumber'
    [err.cannot_create_null_sink]='cannot create null sink "%s".'
    [err.cannot_move_sink_input]='cannot move sink-input %s to "%s".'

    # --- Filename building ---
    [err.invalid_filename_scheme_runtime]='invalid filename_scheme %s'
    [filename.unknown_component]='Unknown'

    # --- Finish screen ---
    [finish.title]='Recording Finished'
    [finish.notification]='Recording session finished'
    [finish.saved_in]='Your recordings are saved in:'
    [finish.press_any_key_exit]='Press any key to exit.'

    # --- CLI ---
    [cli.usage]='loopcatcher v%s

Usage: %s [options]

Behavior:
  - The Welcome screen shows the current configuration and a main menu:
    Continue / Profile / Settings / Restart / About / Exit.
  - Session name is asked interactively (prefilled with a timestamp; just
    press Enter).
  - Output goes to: output-directory/session-name
  - The Recording Wizard walks you through whatever steps your selected
    player profile needs before recording starts automatically.
  - The session ends automatically when playback pauses, stops, or the
    player quits.

Options:
  --debug                   Set log_level to 2 (adds encoder diagnostics to the session log)
  --logname <path>          Session log file path (overrides log_file_path for this run)
  --help                    Show help
  --version                 Show version'
    [cli.unknown_argument]='Unknown argument: %s'
    [cli.version_line]='loopcatcher version %s'
)
