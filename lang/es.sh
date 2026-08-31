# shellcheck shell=bash
###############################################################################
# lang/es.sh - main-script message catalog, Spanish.
#
# Loaded on top of lang/en.sh (the always-loaded fallback baseline) whenever
# Spanish is the active language - see load_lang_dir() in loopcatcher. Only
# needs the ids this translation actually covers: t() falls back to the
# English entry for anything missing here, so this file can lag behind
# lang/en.sh (a newly-added English id) without breaking anything - it just
# shows in English until someone adds the Spanish entry. That's the whole
# point of splitting one file per language: adding or fixing a translation
# here never touches lang/en.sh or any other language's file.
#
# Keep %s placeholder COUNT AND ORDER identical to lang/en.sh's entry for the
# same id - t() passes the same argument list to whichever one it picks.
#
# "declare -gA" (not just "-A") below is required - see lang/en.sh's header
# comment for why: this file is sourced from inside a function, and a plain
# "declare -A" there would create a variable scoped to that function call
# instead of a real global.
###############################################################################

declare -gA MSG_es=(
    # --- dependency / early diagnostics ---
    [dep.missing_command]='no se encontró el comando requerido "%s" en el PATH.'
    [dep.gum_install_hint]='Instálalo con: sudo apt install gum   (Debian 13+; en versiones anteriores usa repo.charm.sh)'
    [dep.missing_encoder]='"%s" es necesario para record_format=%s pero no se encontró'
    [err.requires_tty]='%s requiere una terminal interactiva.'

    # --- generic UI chrome ---
    [ui.cancel_hint]='Pulsa Ctrl+C para cancelar y salir.'
    [ui.cancelled]='Cancelado.'
    [common.back]='< Atrás'
    [common.press_any_key_continue]='Pulsa cualquier tecla para continuar.'
    [common.table.field]='Campo'
    [common.table.value]='Valor'

    # --- config file ---
    [err.cannot_create_config_dir]='no se pudo crear el directorio de configuración: %s'
    [warn.config_mktemp_failed]='no se pudo escribir la configuración (mktemp falló en %s)'
    [err.invalid_record_format]='record_format no válido: %s (permitidos: aac, ogg)'
    [err.invalid_filename_scheme]='filename_scheme no válido: %s (permitidos: normal, strict, strict-lc-nodir)'
    [err.invalid_default_profile]='default_profile no válido: %s (no existe en profiles/, o no está en enabled_profiles)'
    [err.invalid_bitrate]='bitrate no válido: %s (debe ser un entero positivo)'
    [err.invalid_aac_profile]='aac_profile no válido: %s (debe ser un entero positivo)'
    [err.invalid_tail_drain_seconds]='tail_drain_seconds no válido: %s (debe ser un número no negativo, p. ej. 0.35)'
    [err.invalid_log_level]='log_level no válido: %s (permitidos: 0, 1, 2)'
    [err.invalid_language]='language no válido: %s (permitidos: auto, en, es)'
    [err.profile_module_not_found]='no se encontró el módulo de perfil: %s (%s)'

    # --- output directory / session name ---
    [err.no_output_directory]='no se pudo determinar un directorio de salida (HOME no está definido).'
    [err.cannot_create_output_directory]='no se pudo crear el directorio de salida: %s'
    [err.session_name_empty]='El nombre de la sesión no puede estar vacío'
    [err.session_name_dots]="El nombre de la sesión no puede ser '.' ni '..'"
    [err.session_name_slash]="El nombre de la sesión no puede contener '/'"
    [err.cannot_create_session_folder]='no se pudo crear la carpeta de la sesión: %s'
    [session.error.folder_not_empty]='La carpeta de la sesión ya existe y no está vacía: %s'
    [session.intro]='Este es el nombre de la sesión. Se usa para generar la carpeta de destino de lo que se va a grabar, así los archivos existentes no se sobrescriben por accidente.'
    [session.instruction]='Introduce un nombre de sesión ÚNICO que no se haya usado antes.'
    [session.input_header]='Nombre de la sesión (Enter para usar el sugerido, Esc para cancelar)'
    [session.title]='Nombre de la Sesión'

    # --- Welcome / main menu ---
    [welcome.title]='Bienvenida'
    [welcome.message]='Bienvenido a LoopCatcher. Captura el audio de reproducción de tu reproductor de escritorio en archivos organizados y etiquetados automáticamente, listos para usar con la configuración de abajo.'
    [welcome.config_heading]='Configuración'
    [welcome.field.codec]='Códec'
    [welcome.field.aac_profile]='Perfil AAC'
    [welcome.field.bitrate]='Bitrate'
    [welcome.field.player_profile]='Perfil de Reproductor'
    [welcome.field.output_directory]='Directorio de Salida'
    [welcome.menu.header]='Menú principal'
    [welcome.menu.continue]='Continuar'
    [welcome.menu.profile]='Perfil'
    [welcome.menu.settings]='Configuración'
    [welcome.menu.apply_changes]='Aplicar cambios de configuración'
    [welcome.menu.about]='Acerca de'
    [welcome.menu.exit]='Salir'

    # --- Profile menu ---
    [profile.title]='Perfil'
    [profile.menu.header]='Perfil: %s'
    [profile.menu.change]='Cambiar Perfil'
    [profile.menu.settings]='Ajustes del Perfil'
    [profile.menu.about]='Acerca del Perfil'
    [profile.change.header]='Selecciona el perfil predeterminado'
    [profile.settings.header]='Ajustes del Perfil: %s'
    [profile.about.no_readme]='No hay README disponible para este perfil.'

    # --- About (app-level) ---
    [about.title]='Acerca de'
    [about.app_line]='LoopCatcher v%s'
    [about.description]='Un TUI de Linux que captura el audio de reproducción de tu reproductor multimedia de escritorio en archivos organizados y etiquetados automáticamente.'
    [about.license]='Licencia: MIT'
    [about.homepage]='Sitio web: https://github.com/jefonseca/loopcatcher'

    # --- Configuration / Settings ---
    [config.title]='Configuración'
    [config.notify.autosave]='Cada opción de abajo se guarda automáticamente en cuanto la cambias'
    [config.notify.requires_apply]='Los cambios solo se aplican cuando eliges "Aplicar cambios de configuración" en el menú de Bienvenida'
    [config.notify.edit_directly]='También puedes editar el archivo de configuración directamente:'
    [config.header]='Selecciona un grupo'
    [config.group.codecs]='Códecs'
    [config.group.paths]='Rutas'
    [config.group.enabled_profiles]='Perfiles Habilitados'
    [config.group.advanced]='Avanzado'
    [config.codecs.record_format]='Formato de Grabación:  %s'
    [config.codecs.aac_profile]='Perfil AAC:  %s'
    [config.codecs.bitrate]='Bitrate:  %s'
    [config.codecs.record_format_prompt]='Formato de grabación'
    [config.codecs.aac_profile_prompt]='Perfil AAC (solo aplica a aac)'
    [config.codecs.bitrate_prompt]='Bitrate (kbps)'
    [config.paths.output_folder]='Carpeta de Salida:  %s'
    [config.paths.filename_scheme]='Esquema de Nombres:  %s'
    [config.paths.log_file]='Archivo de Registro:  %s'
    [config.paths.filename_scheme_prompt]='Esquema de nombres de archivo'
    [config.paths.log_file_prompt]='Ruta del archivo de registro (vacío para usar el valor por defecto: %s)'
    [config.enabled_profiles.header]='Perfiles Habilitados (el perfil predeterminado siempre está incluido)'
    [config.advanced.tail_drain_seconds]='Segundos de Cola:  %s'
    [config.advanced.log_level]='Nivel de Registro:  %s'
    [config.advanced.nulloutput_name]='Nombre del Sink Nulo:  %s'
    [config.advanced.tail_drain_seconds_prompt]='Segundos de cola (p. ej. 0.35)'
    [config.advanced.log_level_prompt]='Nivel de registro (0=apagado, 1=activado, 2=depuración)'
    [config.advanced.nulloutput_name_prompt]='Nombre del sink nulo'
    [config.top.language]='Idioma:  %s'
    [config.top.language_prompt]='Idioma'

    # --- Recording Wizard (generic step-screen renderer) ---
    [wizard.title]='Asistente de Grabación'
    [wizard.step_label]='Paso %s: %s'
    [wizard.spin.sink]='Esperando el sink de audio...'
    [wizard.spin.stopped]='Esperando a que la reproducción se pause...'
    [wizard.spin.playing]='Esperando a que la reproducción empiece...'
    [wizard.spin.default]='Esperando...'

    # --- Audio server / sink routing ---
    [err.audio_server_unreachable]='no se pudo conectar con el servidor de sesión PulseAudio/PipeWire.'
    [err.audio_server_kde_hint]='En KDE, asegúrate de que pipewire-pulse esté activo en tu sesión de usuario.'
    [err.audio_server_try_hint]='Prueba: systemctl --user status pipewire pipewire-pulse wireplumber'
    [err.cannot_create_null_sink]='no se pudo crear el sink nulo "%s".'
    [err.cannot_move_sink_input]='no se pudo mover el sink-input %s a "%s".'

    # --- Filename building ---
    [err.invalid_filename_scheme_runtime]='filename_scheme no válido %s'
    [filename.unknown_component]='Desconocido'

    # --- Finish screen ---
    [finish.title]='Grabación Finalizada'
    [finish.notification]='La sesión de grabación ha finalizado'
    [finish.saved_in]='Tus grabaciones se guardaron en:'
    [finish.press_any_key_exit]='Pulsa cualquier tecla para salir.'

    # --- CLI ---
    [cli.usage]='loopcatcher v%s

Uso: %s [opciones]

Comportamiento:
  - La pantalla de Bienvenida muestra la configuración actual y un menú
    principal: Continuar / Perfil / Configuración / Reiniciar / Acerca de /
    Salir.
  - El nombre de la sesión se pide de forma interactiva (con una marca de
    tiempo sugerida; basta con pulsar Enter).
  - La salida va a: directorio-de-salida/nombre-de-sesión
  - El Asistente de Grabación te guía para crear el sink de audio, pausar
    y luego iniciar la reproducción para empezar a grabar automáticamente.
  - La sesión termina automáticamente cuando la reproducción se pausa, se
    detiene o el reproductor se cierra.

Opciones:
  --debug                   Pone log_level en 2 (añade diagnósticos del codificador al registro de sesión)
  --logname <ruta>          Ruta del archivo de registro de sesión (sobreescribe log_file_path solo para esta ejecución)
  --help                    Muestra la ayuda
  --version                 Muestra la versión'
    [cli.unknown_argument]='Argumento desconocido: %s'
    [cli.version_line]='loopcatcher versión %s'

    # --- spotify_native module screens (Wizard steps + Recording screen) ---
    [spotify_native.wizard.step1_heading]='Crear el Sink de Audio'
    [spotify_native.wizard.step1_line1]='1) Abre tu %s'
    [spotify_native.wizard.step1_line2]='2) Reproduce cualquier pista que NO sea la primera de la lista o álbum que quieres grabar'
    [spotify_native.wizard.step2_heading]='Prepárate para grabar'
    [spotify_native.wizard.step2_line1]='1) Pausa la reproducción en tu %s'
    [spotify_native.wizard.step3_heading]='Empezar a grabar'
    [spotify_native.wizard.step3_line1]='1) Reproduce la primera pista de tu lista o álbum para empezar a grabar automáticamente'
    [spotify_native.recording.title]='Grabación'
    [spotify_native.table.info]='Info'
    [spotify_native.table.metadata]='Metadatos'
    [spotify_native.table.status]='Estado'
    [spotify_native.field.output_folder]='Carpeta de Salida'
    [spotify_native.field.session_name]='Nombre de Sesión'
    [spotify_native.field.config_file]='Archivo de Configuración'
    [spotify_native.field.audio_sink]='Sink de Audio'
    [spotify_native.field.artist]='Artista'
    [spotify_native.field.album]='Álbum'
    [spotify_native.field.track]='Pista'
    [spotify_native.field.track_no]='N.º de Pista'
    [spotify_native.field.disc_no]='N.º de Disco'
    [spotify_native.field.output_file]='Archivo de Salida'
    [spotify_native.field.catcher_status]='Estado de Captura'
    [spotify_native.field.playback_status]='Estado de Reproducción'
    [spotify_native.status.recording]='Grabando'
    [spotify_native.status.failed]='Fallido'
    [spotify_native.status.spinner_suffix]='%s...'
    [spotify_native.error.dbus_monitor_ended]='loopcatcher: dbus-monitor terminó, la sesión se detuvo.'
)
