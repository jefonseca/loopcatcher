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
# Strings that belong to the spotify_native module's SCREENS (Recording
# Wizard step text, Recording screen table/labels) live here too, under the
# spotify_native.* namespace - screens are rendered with this script's
# generic elements even when a module drives them, so they're catalogued
# alongside the rest of the app rather than in the module's own lang/
# (which is reserved for the module's own IDENTITY data: its friendly label
# and its Profile Settings field labels - see profiles/spotify_native/lang/).
#
# Every entry is a plain string, used either as-is ("$(t some.id)") or as a
# printf format consumed with extra args ("$(t some.id "$value")"). Keep %s
# placeholder COUNT AND ORDER identical to every other language's entry for
# the same id - t() passes the same argument list to whichever one it picks.
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
    [ui.cancel_hint]='Press Ctrl+C to cancel and exit.'
    [ui.cancelled]='Cancelled.'
    [common.back]='< Back'
    [common.press_any_key_continue]='Press any key to continue.'
    [common.table.field]='Field'
    [common.table.value]='Value'

    # --- config file ---
    [err.cannot_create_config_dir]='cannot create config directory: %s'
    [warn.config_mktemp_failed]='could not write config (mktemp failed in %s)'
    [err.invalid_record_format]='Invalid record_format: %s (allowed: aac, ogg)'
    [err.invalid_filename_scheme]='Invalid filename_scheme: %s (allowed: normal, strict, strict-lc-nodir)'
    [err.invalid_default_profile]='Invalid default_profile: %s (not found under profiles/, or not in enabled_profiles)'
    [err.invalid_bitrate]='Invalid bitrate: %s (must be a positive integer)'
    [err.invalid_aac_profile]='Invalid aac_profile: %s (must be a positive integer)'
    [err.invalid_tail_drain_seconds]='Invalid tail_drain_seconds: %s (must be a non-negative number, e.g. 0.35)'
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
    [welcome.message]='Welcome to LoopCatcher. It captures loopback audio from your desktop media player into organized, auto-tagged audio files, ready to use with the configuration below.'
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
    [about.app_line]='LoopCatcher v%s'
    [about.description]='A Linux TUI that captures desktop media player loopback audio into organized, auto-tagged audio files.'
    [about.license]='License: MIT'
    [about.homepage]='Homepage: https://github.com/jefonseca/loopcatcher'

    # --- Configuration / Settings ---
    [config.title]='Configuration'
    [config.notify.autosave]='Every option below is saved automatically as soon as you change it'
    [config.notify.requires_apply]='Changes only take effect once you pick "Apply configuration change" from the Welcome menu'
    [config.notify.edit_directly]='You can also edit the config file directly:'
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
  - The Recording Wizard walks you through creating the audio sink, pausing,
    then starting playback to begin recording automatically.
  - The session ends automatically when playback pauses, stops, or the
    player quits.

Options:
  --debug                   Set log_level to 2 (adds encoder diagnostics to the session log)
  --logname <path>          Session log file path (overrides log_file_path for this run)
  --help                    Show help
  --version                 Show version'
    [cli.unknown_argument]='Unknown argument: %s'
    [cli.version_line]='loopcatcher version %s'

    # --- spotify_native module screens (Wizard steps + Recording screen) ---
    [spotify_native.wizard.step1_heading]='Create the Audio Sink'
    [spotify_native.wizard.step1_line1]='1) Open your %s'
    [spotify_native.wizard.step1_line2]='2) Play any track that is NOT the first in your playlist or album you want to record'
    [spotify_native.wizard.step2_heading]='Prepare to record'
    [spotify_native.wizard.step2_line1]='1) Pause the playback on your %s'
    [spotify_native.wizard.step3_heading]='Start recording'
    [spotify_native.wizard.step3_line1]='1) Play the first track of your playlist or album to start the recording automatically'
    [spotify_native.recording.title]='Recording'
    [spotify_native.table.info]='Info'
    [spotify_native.table.metadata]='Metadata'
    [spotify_native.table.status]='Status'
    [spotify_native.field.output_folder]='Output Folder'
    [spotify_native.field.session_name]='Session Name'
    [spotify_native.field.config_file]='Config File'
    [spotify_native.field.audio_sink]='Audio Sink'
    [spotify_native.field.artist]='Artist'
    [spotify_native.field.album]='Album'
    [spotify_native.field.track]='Track'
    [spotify_native.field.track_no]='Track No.'
    [spotify_native.field.disc_no]='Disc No.'
    [spotify_native.field.output_file]='Output File'
    [spotify_native.field.catcher_status]='Catcher Status'
    [spotify_native.field.playback_status]='Playback Status'
    [spotify_native.status.recording]='Recording'
    [spotify_native.status.failed]='Failed'
    [spotify_native.status.spinner_suffix]='%s...'
    [spotify_native.error.dbus_monitor_ended]='loopcatcher: dbus-monitor ended, session stopped.'
)
