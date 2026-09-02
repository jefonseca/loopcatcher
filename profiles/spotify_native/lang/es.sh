# shellcheck shell=bash
###############################################################################
# profiles/spotify_native/lang/es.sh - every Spanish string this
# module owns (identity data AND on-screen text - see en.sh's header for why
# both live in this same file). Loaded on top of this same directory's en.sh
# whenever Spanish is the active language. Only needs the ids this
# translation actually covers - t() falls back to the English entry for
# anything missing here.
###############################################################################

MSG_es[spotify_native.label]='Reproductor oficial de Spotify (gestionado)'
MSG_es[spotify_native.title]='Spotify (Gestionado)'

# --- Etiquetas del esquema de Configuración de Perfil (profile_config_schema()) ---
MSG_es[spotify_native.field.manage_player]='Gestionar Spotify (yes = loopcatcher lo abre y lo controla)'
MSG_es[spotify_native.field.sink_app_name]='Nombre de la App del Sink'
MSG_es[spotify_native.field.mpris_bus]='Bus MPRIS'
MSG_es[spotify_native.field.mpris_wait_timeout_seconds]='Tiempo de Espera MPRIS (segundos)'
MSG_es[spotify_native.field.sink_match]='Coincidencia de Sink (globs separados por espacios)'

# --- Pantalla de Requisitos (requirements_screen()) ---
MSG_es[spotify_native.requirements.attention]='LEA ESTO ANTES DE CONTINUAR!!!'
# Todo el panel es UN solo mensaje a propósito: se lee como texto conectado,
# así que se traduce como texto conectado. Mantén cada línea en ~85
# caracteres o menos - gum parte a mitad de frase cualquier línea más larga.
MSG_es[spotify_native.requirements.body]='Spotify debe estar instalado (https://flathub.org/apps/com.spotify.Client).
Spotify debe estar cerrado - este perfil lo inicia él mismo.
DEBES desactivar estos ajustes en Spotify antes de empezar:
* Reproducción automática (Autoplay)
* Fundido entre canciones (Crossfade)
* Reproducción sin pausas (Gapless)
* Automix
Recomendaciones: Descarga antes la lista/álbum para evitar cortes de carga, o fija una Calidad de Transmisión estable (Normal/Alta/Muy Alta).'
MSG_es[spotify_native.requirements.confirm]='He leído los requisitos y recomendaciones y tengo todo preparado'

# --- Prompts de acción compartidos (requirements_screen()/fatal_exit_screen()) ---
MSG_es[spotify_native.action.header]='¿Qué deseas hacer?'
MSG_es[spotify_native.action.exit]='Salir'

# --- Fallos de detección/lanzamiento/espera MPRIS (profile_run()) ---
MSG_es[spotify_native.error.not_installed_body]='No se encontró Spotify en este sistema (nativo, Flatpak o Snap).

Instálalo desde Flathub y vuelve a ejecutar loopcatcher:
https://flathub.org/apps/com.spotify.Client'
MSG_es[spotify_native.error.already_running]='Spotify ya está abierto. Ciérralo y vuelve a ejecutar loopcatcher.'
MSG_es[spotify_native.wizard.launch_heading]='Iniciando Spotify'
MSG_es[spotify_native.wizard.launch_line1]='Lanzando Spotify con el sink de captura ya seleccionado...'
MSG_es[spotify_native.wizard.spin_launch]='Esperando a que Spotify aparezca en MPRIS...'
MSG_es[spotify_native.wizard.loading_heading]='Cargando Spotify'
MSG_es[spotify_native.wizard.loading_line1]='Dando a Spotify un momento para terminar de iniciar...'
MSG_es[spotify_native.wizard.spin_loading]='Esperando a que cargue Spotify...'
MSG_es[spotify_native.error.mpris_timeout]='Spotify no llegó a MPRIS en %s segundos. Ciérralo y reintenta.'
MSG_es[spotify_native.error.openuri_failed]='No se pudo iniciar la reproducción. Ciérralo y reintenta.'
MSG_es[spotify_native.wizard.sink_heading]='Localizando el flujo de audio'
MSG_es[spotify_native.wizard.sink_line1]='Esperando el sink de captura - puede tardar unos segundos.'

# --- Pantalla de entrada de URL (url_input_screen()) ---
MSG_es[spotify_native.url.intro]='Pega el enlace de Spotify que quieres grabar (canción/álbum/lista).'
MSG_es[spotify_native.url.instruction]='Soportado: enlaces de canción, álbum y lista de open.spotify.com.'
MSG_es[spotify_native.url.input_header]='URL de Spotify'
MSG_es[spotify_native.error.invalid_url]='Ese enlace de Spotify no es válido. Inténtalo de nuevo.'

# --- Pantalla de Grabación (recording_screen_render()) ---
MSG_es[spotify_native.recording.title]='Grabación'
MSG_es[spotify_native.recording.metadata_heading]='Metadatos'
MSG_es[spotify_native.field.output_folder]='Carpeta de Salida'
MSG_es[spotify_native.field.session_name]='Nombre de Sesión'
MSG_es[spotify_native.field.catcher_status]='Estado de Captura'
MSG_es[spotify_native.field.artist]='Artista'
MSG_es[spotify_native.field.album]='Álbum'
MSG_es[spotify_native.field.track]='Pista'
MSG_es[spotify_native.status.recording]='Grabando'
MSG_es[spotify_native.status.failed]='Fallido'
MSG_es[spotify_native.error.dbus_monitor_ended]='loopcatcher: dbus-monitor terminó, la sesión se detuvo.'

# --- Wizard steps used only when manage_player=no (the user drives Spotify) ---
MSG_es[spotify_native.wizard.step1_heading]='Crear el Sink de Audio'
MSG_es[spotify_native.wizard.step1_body]='1) Abre tu %s
2) Reproduce una pista que NO sea la primera que quieres grabar'
MSG_es[spotify_native.wizard.step2_heading]='Prepárate para grabar'
MSG_es[spotify_native.wizard.step2_line1]='1) Pausa la reproducción en tu %s'
MSG_es[spotify_native.wizard.step3_heading]='Empezar a grabar'
MSG_es[spotify_native.wizard.step3_line1]='1) Reproduce la primera pista - la grabación empieza sola'
