# shellcheck shell=bash
###############################################################################
# profiles/spotify_native/lang/en.sh - this module's OWN identity data,
# English: its friendly label and its Profile Settings field labels. Pure
# data (no functions, no side effects, no recording-state vars) - split out
# from profile.sh so it's cheap and safe to source for ANY discovered module
# just to look up its name (e.g. a future friendly-name picker), not only the
# currently active one. English is this module's own fallback baseline too -
# every id this module defines must exist here - loaded first, then the
# active language's own file from this same directory (if different) is
# loaded on top as an overlay. Adds entries into the SAME MSG_en array
# lang/en.sh (main catalog) already declared - loopcatcher's t() is the only
# lookup mechanism, shared by the main script and every module alike.
#
# Everything else this module shows on screen (Recording Wizard step text,
# Recording screen table/labels) lives in the main lang/en.sh instead, under
# the same spotify_native.* namespace - see the comment at the top of that
# file for why.
###############################################################################

MSG_en[spotify_native.label]='Spotify official player'
MSG_en[spotify_native.field.sink_app_name]='Sink App Name'
MSG_en[spotify_native.field.mpris_bus]='MPRIS Bus'
MSG_en[spotify_native.field.sink_match]='Sink Match (space-separated globs)'
