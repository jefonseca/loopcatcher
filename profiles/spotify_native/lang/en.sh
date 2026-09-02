# shellcheck shell=bash
###############################################################################
# profiles/spotify_native/lang/en.sh - every English string this
# module owns: its identity data (friendly label, Profile Settings field
# labels) AND everything it shows on screen (the Requirements screen, the
# install/launch/URL-input flow, the Recording screen). Pure data (no
# functions, no side effects, no recording-state vars) - split out from
# profile.sh so it's cheap and safe to source on its own. Keeping the whole
# module's string set here, not split between here and the main lang/en.sh,
# means deleting this directory removes every string this module owns -
# nothing of it is left orphaned in the main catalog. English is this
# module's own fallback baseline too - every id this module defines must
# exist here - loaded first, then the active language's own file from this
# same directory (if different) is loaded on top as an overlay. Adds entries
# into the SAME MSG_en array lang/en.sh (main catalog) already declared -
# loopcatcher's t() is the only lookup mechanism, shared by the main script
# and every module alike.
###############################################################################

MSG_en[spotify_native.label]='Spotify official player (managed)'
MSG_en[spotify_native.title]='Spotify (Managed)'

# --- Profile Settings schema labels (profile_config_schema()) ---
MSG_en[spotify_native.field.manage_player]='Manage Spotify (yes = loopcatcher launches and drives it)'
MSG_en[spotify_native.field.sink_app_name]='Sink App Name'
MSG_en[spotify_native.field.mpris_bus]='MPRIS Bus'
MSG_en[spotify_native.field.mpris_wait_timeout_seconds]='MPRIS Wait Timeout (seconds)'
MSG_en[spotify_native.field.sink_match]='Sink Match (space-separated globs)'

# --- Requirements screen (requirements_screen()) ---
MSG_en[spotify_native.requirements.attention]='READ THIS BEFORE CONTINUING!!!'
# The whole panel is ONE message on purpose: it reads as connected text, so a
# translator should be able to rewrite it as connected text. Keep each line at
# or under ~85 characters - gum hard-wraps anything longer mid-sentence.
MSG_en[spotify_native.requirements.body]='Spotify must be installed (https://flathub.org/apps/com.spotify.Client).
Spotify must be closed - this profile launches it itself.
You MUST disable these settings in the Spotify client before starting:
* Autoplay
* Crossfade songs
* Gapless playback
* Automix
Recommendations: Download the playlist/album beforehand to avoid loading gaps, or set a fixed Stream Quality (Normal/High/Very High).'
MSG_en[spotify_native.requirements.confirm]="I've read the requirements and recommendations and I'm ready"

# --- Shared action prompts (requirements_screen()/fatal_exit_screen()) ---
MSG_en[spotify_native.action.header]='What do you want to do?'
MSG_en[spotify_native.action.exit]='Exit'

# --- Install detection / launch / MPRIS-wait failures (profile_run()) ---
MSG_en[spotify_native.error.not_installed_body]='Spotify was not found (checked: native, Flatpak and Snap).

Install it, ideally via Flathub, then run loopcatcher again:
https://flathub.org/apps/com.spotify.Client'
MSG_en[spotify_native.error.already_running]='Spotify is already running. Close it, then run loopcatcher again.'
MSG_en[spotify_native.wizard.launch_heading]='Starting Spotify'
MSG_en[spotify_native.wizard.launch_line1]='Launching Spotify with the capture sink already selected...'
MSG_en[spotify_native.wizard.spin_launch]='Waiting for Spotify to appear on MPRIS...'
MSG_en[spotify_native.wizard.loading_heading]='Loading Spotify'
MSG_en[spotify_native.wizard.loading_line1]='Giving Spotify a moment to finish starting up before continuing...'
MSG_en[spotify_native.wizard.spin_loading]='Waiting for Spotify to load...'
MSG_en[spotify_native.error.mpris_timeout]='Spotify did not reach MPRIS in %s seconds. Close it and retry.'
MSG_en[spotify_native.error.openuri_failed]='Could not start playback on Spotify. Close it and try again.'
MSG_en[spotify_native.wizard.sink_heading]='Locating the audio stream'
MSG_en[spotify_native.wizard.sink_line1]='Waiting for the capture sink - can take a few seconds.'

# --- URL input screen (url_input_screen()) ---
MSG_en[spotify_native.url.intro]='Paste the Spotify link you want to record (track/album/playlist).'
MSG_en[spotify_native.url.instruction]='Supported: track, album, and playlist links from open.spotify.com.'
MSG_en[spotify_native.url.input_header]='Spotify URL'
MSG_en[spotify_native.error.invalid_url]="That is not a valid Spotify link. Please try again."

# --- Recording screen (recording_screen_render()) ---
MSG_en[spotify_native.recording.title]='Recording'
MSG_en[spotify_native.recording.metadata_heading]='Metadata'
MSG_en[spotify_native.field.output_folder]='Output Folder'
MSG_en[spotify_native.field.session_name]='Session Name'
MSG_en[spotify_native.field.catcher_status]='Catcher Status'
MSG_en[spotify_native.field.artist]='Artist'
MSG_en[spotify_native.field.album]='Album'
MSG_en[spotify_native.field.track]='Track'
MSG_en[spotify_native.status.recording]='Recording'
MSG_en[spotify_native.status.failed]='Failed'
MSG_en[spotify_native.error.dbus_monitor_ended]='loopcatcher: dbus-monitor ended, session stopped.'

# --- Wizard steps used only when manage_player=no (the user drives Spotify) ---
MSG_en[spotify_native.wizard.step1_heading]='Create the Audio Sink'
MSG_en[spotify_native.wizard.step1_body]='1) Open your %s
2) Play any track that is NOT the first one you want to record'
MSG_en[spotify_native.wizard.step2_heading]='Prepare to record'
MSG_en[spotify_native.wizard.step2_line1]='1) Pause the playback on your %s'
MSG_en[spotify_native.wizard.step3_heading]='Start recording'
MSG_en[spotify_native.wizard.step3_line1]='1) Play the first track you want - recording starts on its own'
