#!/usr/bin/env bash
# ==============================================================================
# dorsett-network.sh — CLI de gestión de conectividad y fallback (Dorsett v0.4.0)
# ==============================================================================
# Gestiona los modos HOME, MOBILE y NOMAD mediante NetworkManager (nmcli).
# No compite con NetworkManager ni depende de acceso a Internet.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

# --- Códigos de salida significativos ---
readonly EXIT_OK=0
readonly EXIT_GENERAL=1
readonly EXIT_USAGE=2
readonly EXIT_NM_UNAVAILABLE=3
readonly EXIT_LOCK_BUSY=4
readonly EXIT_PROFILE_MISSING=5
readonly EXIT_REMOTE_UNSAFE=6
readonly EXIT_TRANSITION_FAILED=7
readonly EXIT_PRIVILEGE=8

# --- Valores por defecto (sobreescribibles por archivo de configuración) ---
DEFAULT_CONFIG="/etc/dorsett/network.env"
CONFIG_FILE="${DORSETT_CONFIG:-$DEFAULT_CONFIG}"

WIFI_INTERFACE="wlan0"
HOME_PROFILE="home-profile"
MOBILE_PROFILE="mobile-profile"
AP_PROFILE="Dorsett-AP"
AP_SSID="Dorsett-AP"
AP_ADDRESS="10.42.0.1/24"
AP_BAND="bg"
AP_CHANNEL="6"
FALLBACK_TIMEOUT="30"
ROLLBACK_TIMEOUT="120"
NMCLI_TIMEOUT="20"
LOCK_FILE="${DORSETT_LOCK_FILE:-/run/dorsett-network.lock}"
STATE_DIR="${DORSETT_STATE_DIR:-}"

# --- Opciones de ejecución ---
DRY_RUN=0
FORCE_LOCAL=0
CUSTOM_ROLLBACK_SECONDS=""
COMMAND=""

# --- Binarios (permiten inyección de mocks en pruebas) ---
NMCLI_BIN="${DORSETT_NMCLI_BIN:-nmcli}"
IP_BIN="${DORSETT_IP_BIN:-ip}"
SYSTEMD_RUN_BIN="${DORSETT_SYSTEMD_RUN_BIN:-systemd-run}"
SYSTEMCTL_BIN="${DORSETT_SYSTEMCTL_BIN:-systemctl}"
LOGGER_BIN="${DORSETT_LOGGER_BIN:-logger}"

LOCK_FD_OPEN=0
LOCK_DIR_FALLBACK=""

log_msg() {
    local level="$1"
    shift
    local msg="$*"
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >&2
    if [[ "$DRY_RUN" -eq 0 ]] && command -v "$LOGGER_BIN" >/dev/null 2>&1; then
        "$LOGGER_BIN" -t dorsett-network "[$level] $msg" 2>/dev/null || true
    fi
}

die() {
    local code="$1"
    shift
    log_msg "ERROR" "$*"
    exit "$code"
}

usage() {
    cat <<'EOF'
Uso: dorsett-network [OPCIONES] <COMANDO>

Comandos:
  status      Muestra interfaz, perfil activo, modo detectado e IPv4.
  fallback    Ejecuta la selección de respaldo al arranque (ventana acotada).
  home        Cambia manualmente al perfil HOME autorizado.
  mobile      Cambia manualmente al perfil MOBILE (hotspot del smartphone).
  nomad       Cambia manualmente al Access Point NOMAD (Dorsett-AP).
  confirm     Cancela el temporizador de rollback tras verificar conectividad.
  rollback    Restaura manualmente el perfil previo guardado por un cambio remoto.
  help        Muestra esta ayuda.

Opciones:
  --config <ruta>              Archivo de configuración (por defecto /etc/dorsett/network.env).
  --dry-run                    Simula la operación sin modificar la red ni el sistema.
  --rollback-seconds <seg>     Ventana de reversión automática en transiciones remotas.
  --force-local                Confirma ejecución en consola local (no omite bloqueo remoto SSH).
  -h, --help                   Muestra esta ayuda.

Notas de seguridad:
  - Cambiar de modo manualmente puede interrumpir sesiones SSH y WayVNC activas.
  - Desde una sesión remota (SSH), se exige un temporizador de rollback independiente
    de la sesión (systemd-run). Si no está disponible, la transición se rechaza.
EOF
}

is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

is_nonneg_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

validate_config() {
    [[ "$WIFI_INTERFACE" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "$EXIT_USAGE" "WIFI_INTERFACE inválido: $WIFI_INTERFACE"
    [[ -n "$HOME_PROFILE" ]] || die "$EXIT_USAGE" "HOME_PROFILE no puede estar vacío"
    [[ -n "$MOBILE_PROFILE" ]] || die "$EXIT_USAGE" "MOBILE_PROFILE no puede estar vacío"
    [[ -n "$AP_PROFILE" ]] || die "$EXIT_USAGE" "AP_PROFILE no puede estar vacío"
    [[ "$AP_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || die "$EXIT_USAGE" "AP_ADDRESS CIDR inválido: $AP_ADDRESS"
    is_nonneg_int "$FALLBACK_TIMEOUT" || die "$EXIT_USAGE" "FALLBACK_TIMEOUT inválido: $FALLBACK_TIMEOUT"
    is_positive_int "$ROLLBACK_TIMEOUT" || die "$EXIT_USAGE" "ROLLBACK_TIMEOUT inválido: $ROLLBACK_TIMEOUT"
    is_positive_int "$NMCLI_TIMEOUT" || die "$EXIT_USAGE" "NMCLI_TIMEOUT inválido: $NMCLI_TIMEOUT"
}

load_config_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    [[ -r "$path" ]] || die "$EXIT_PRIVILEGE" "No se puede leer el archivo de configuración: $path"

    if [[ "$EUID" -eq 0 ]] && [[ "$DRY_RUN" -eq 0 ]]; then
        local owner_uid perms
        owner_uid="$(stat -c '%u' "$path" 2>/dev/null || echo '')"
        perms="$(stat -c '%a' "$path" 2>/dev/null || echo '')"
        if [[ -n "$owner_uid" ]] && [[ "$owner_uid" != "0" ]]; then
            die "$EXIT_PRIVILEGE" "Configuración insegura: $path debe pertenecer a root"
        fi
        if [[ -n "$perms" ]] && [[ "$perms" != "600" ]] && [[ "$perms" != "640" ]] && [[ "$perms" != "400" ]]; then
            log_msg "WARN" "Permisos recomendados para $path son 0600 (actual: $perms)"
        fi
    fi

    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # Quitar espacios finales antes de revisar comillas
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            if [[ "$val" =~ ^\"(.*)\"$ ]]; then
                val="${BASH_REMATCH[1]}"
            elif [[ "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            case "$key" in
                WIFI_INTERFACE) WIFI_INTERFACE="$val" ;;
                HOME_PROFILE) HOME_PROFILE="$val" ;;
                MOBILE_PROFILE) MOBILE_PROFILE="$val" ;;
                AP_PROFILE) AP_PROFILE="$val" ;;
                AP_SSID) AP_SSID="$val" ;;
                AP_ADDRESS) AP_ADDRESS="$val" ;;
                AP_BAND) AP_BAND="$val" ;;
                AP_CHANNEL) AP_CHANNEL="$val" ;;
                FALLBACK_TIMEOUT) FALLBACK_TIMEOUT="$val" ;;
                ROLLBACK_TIMEOUT) ROLLBACK_TIMEOUT="$val" ;;
                NMCLI_TIMEOUT) NMCLI_TIMEOUT="$val" ;;
                LOCK_FILE) LOCK_FILE="$val" ;;
                STATE_DIR) STATE_DIR="$val" ;;
                *) log_msg "WARN" "Clave desconocida ignorada en configuración: $key" ;;
            esac
        fi
    done < "$path"
}

resolve_state_dir() {
    if [[ -n "$STATE_DIR" ]]; then
        return 0
    fi
    if [[ "$EUID" -eq 0 ]]; then
        STATE_DIR="/run/dorsett"
    else
        STATE_DIR="${TMPDIR:-/tmp}/dorsett-${USER:-user}"
    fi
}

cleanup_lock() {
    if [[ "$LOCK_FD_OPEN" -eq 1 ]]; then
        exec 9>&- || true
        LOCK_FD_OPEN=0
    fi
    if [[ -n "$LOCK_DIR_FALLBACK" ]] && [[ -d "$LOCK_DIR_FALLBACK" ]]; then
        rmdir "$LOCK_DIR_FALLBACK" 2>/dev/null || true
        LOCK_DIR_FALLBACK=""
    fi
}

acquire_lock() {
    local lock_wait="${DORSETT_LOCK_TIMEOUT:-2}"
    local lock_parent
    lock_parent="$(dirname "$LOCK_FILE")"

    if [[ ! -d "$lock_parent" ]] || [[ ! -w "$lock_parent" ]]; then
        if [[ "$EUID" -ne 0 ]]; then
            LOCK_FILE="${TMPDIR:-/tmp}/dorsett-network-${USER:-user}.lock"
        else
            mkdir -p "$lock_parent"
        fi
    fi

    if command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE"
        LOCK_FD_OPEN=1
        if [[ "$lock_wait" -eq 0 ]]; then
            flock -n 9 || die "$EXIT_LOCK_BUSY" "Otra instancia de dorsett-network está en ejecución ($LOCK_FILE)"
        else
            flock -w "$lock_wait" 9 || die "$EXIT_LOCK_BUSY" "Tiempo agotado esperando bloqueo de dorsett-network ($LOCK_FILE)"
        fi
    else
        local lockdir="${LOCK_FILE}.d"
        local waited=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            if [[ "$waited" -ge "$lock_wait" ]]; then
                die "$EXIT_LOCK_BUSY" "Otra instancia de dorsett-network está en ejecución ($lockdir)"
            fi
            sleep 1
            waited=$((waited + 1))
        done
        LOCK_DIR_FALLBACK="$lockdir"
    fi
    trap cleanup_lock EXIT
}

run_nmcli() {
    if command -v timeout >/dev/null 2>&1; then
        LC_ALL=C timeout "$NMCLI_TIMEOUT" "$NMCLI_BIN" "$@"
    else
        LC_ALL=C "$NMCLI_BIN" "$@"
    fi
}

check_dependencies() {
    command -v "$NMCLI_BIN" >/dev/null 2>&1 || die "$EXIT_NM_UNAVAILABLE" "No se encontró nmcli ($NMCLI_BIN)"
    local nm_running
    nm_running="$(run_nmcli -t -f RUNNING general 2>/dev/null || true)"
    [[ "$nm_running" == "running" ]] || die "$EXIT_NM_UNAVAILABLE" "NetworkManager no está activo o no responde"

    local dev_line
    dev_line="$(run_nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: -v iface="$WIFI_INTERFACE" '$1 == iface {print $0; exit}')"
    [[ -n "$dev_line" ]] || die "$EXIT_NM_UNAVAILABLE" "Interfaz $WIFI_INTERFACE no encontrada en NetworkManager"
}

require_privileges() {
    if [[ "$DRY_RUN" -eq 1 ]] || [[ "${DORSETT_ALLOW_NONROOT:-0}" == "1" ]]; then
        return 0
    fi
    if [[ "$EUID" -ne 0 ]]; then
        die "$EXIT_PRIVILEGE" "Este comando requiere privilegios de root (usa sudo)."
    fi
}

get_device_state_code() {
    local raw
    raw="$(run_nmcli -g GENERAL.STATE device show "$WIFI_INTERFACE" 2>/dev/null | head -n1 || true)"
    if [[ "$raw" =~ ^([0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '0\n'
    fi
}

get_active_connection() {
    local conn
    conn="$(run_nmcli -g GENERAL.CONNECTION device show "$WIFI_INTERFACE" 2>/dev/null | head -n1 || true)"
    if [[ "$conn" == "--" ]]; then
        conn=""
    fi
    printf '%s\n' "$conn"
}

profile_exists() {
    local profile="$1"
    run_nmcli -g connection.id connection show "$profile" >/dev/null 2>&1
}

get_profile_wifi_mode() {
    local profile="$1"
    [[ -n "$profile" ]] || return 0
    run_nmcli -g 802-11-wireless.mode connection show "$profile" 2>/dev/null | head -n1 || true
}

is_valid_local_ipv4() {
    local cidr="$1"
    local ip="${cidr%/*}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    # Descartar link-local 169.254.0.0/16 y 0.0.0.0
    if [[ "$ip" == 169.254.* ]] || [[ "$ip" == 0.* ]]; then
        return 1
    fi
    return 0
}

get_valid_ipv4_cidr() {
    local line addr
    if command -v "$IP_BIN" >/dev/null 2>&1; then
        while IFS= read -r line; do
            addr="$(awk '{print $4}' <<< "$line")"
            if is_valid_local_ipv4 "$addr"; then
                printf '%s\n' "$addr"
                return 0
            fi
        done < <("$IP_BIN" -4 -o addr show dev "$WIFI_INTERFACE" 2>/dev/null || true)
    fi

    # Respaldo mediante nmcli si ip no devuelve dirección o en entornos simulados
    while IFS= read -r addr; do
        addr="${addr//[[:space:]]/}"
        if is_valid_local_ipv4 "$addr"; then
            printf '%s\n' "$addr"
            return 0
        fi
    done < <(run_nmcli -g IP4.ADDRESS device show "$WIFI_INTERFACE" 2>/dev/null | tr '|' '\n' || true)

    return 1
}

detect_current_mode() {
    local state_code active_conn ipv4 wifi_mode expected_ap_ip
    state_code="$(get_device_state_code)"
    active_conn="$(get_active_connection)"
    ipv4="$(get_valid_ipv4_cidr || true)"
    expected_ap_ip="${AP_ADDRESS%/*}"

    if [[ "$state_code" -eq 100 ]] && [[ -n "$active_conn" ]] && [[ -n "$ipv4" ]]; then
        wifi_mode="$(get_profile_wifi_mode "$active_conn")"
        if [[ "$active_conn" == "$AP_PROFILE" ]] || [[ "$wifi_mode" == "ap" ]]; then
            if [[ "${ipv4%/*}" == "$expected_ap_ip" ]]; then
                printf 'NOMAD\n'
            else
                printf 'NOMAD_DEGRADED\n'
            fi
        elif [[ "$active_conn" == "$HOME_PROFILE" ]]; then
            printf 'HOME\n'
        elif [[ "$active_conn" == "$MOBILE_PROFILE" ]]; then
            printf 'MOBILE\n'
        else
            printf 'UNKNOWN\n'
        fi
    elif [[ "$state_code" -eq 100 ]]; then
        printf 'NO_VALID_IP\n'
    elif [[ "$state_code" -ge 40 ]] && [[ "$state_code" -lt 100 ]]; then
        printf 'ACTIVATING\n'
    else
        printf 'DISCONNECTED\n'
    fi
}

cmd_status() {
    check_dependencies
    local state_code state_raw active_conn ipv4 mode wifi_mode
    state_raw="$(run_nmcli -g GENERAL.STATE device show "$WIFI_INTERFACE" 2>/dev/null | head -n1 || echo 'unknown')"
    state_code="$(get_device_state_code)"
    active_conn="$(get_active_connection)"
    ipv4="$(get_valid_ipv4_cidr || echo 'none')"
    mode="$(detect_current_mode)"
    wifi_mode=""
    if [[ -n "$active_conn" ]]; then
        wifi_mode="$(get_profile_wifi_mode "$active_conn")"
    fi

    printf 'interface=%s\n' "$WIFI_INTERFACE"
    printf 'device_state=%s\n' "$state_raw"
    printf 'device_state_code=%s\n' "$state_code"
    printf 'active_profile=%s\n' "${active_conn:-none}"
    printf 'wifi_mode=%s\n' "${wifi_mode:-none}"
    printf 'ipv4=%s\n' "$ipv4"
    printf 'detected_mode=%s\n' "$mode"
}

activate_profile() {
    local target="$1"
    profile_exists "$target" || die "$EXIT_PROFILE_MISSING" "El perfil '$target' no existe en NetworkManager. Ningún cambio aplicado."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_msg "INFO" "[DRY-RUN] Se activaría el perfil '$target' en $WIFI_INTERFACE (nmcli --wait $NMCLI_TIMEOUT connection up \"$target\")"
        return 0
    fi

    run_nmcli --wait "$NMCLI_TIMEOUT" connection up "$target" >/dev/null \
        || die "$EXIT_TRANSITION_FAILED" "Falló la activación del perfil '$target'"
}

cmd_fallback() {
    require_privileges
    acquire_lock
    check_dependencies

    local elapsed=0
    local step=2
    local state_code ipv4 mode active_conn

    while true; do
        mode="$(detect_current_mode)"
        case "$mode" in
            HOME|MOBILE|NOMAD|UNKNOWN)
                break
                ;;
        esac

        if [[ "$elapsed" -ge "$FALLBACK_TIMEOUT" ]]; then
            break
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_msg "INFO" "[DRY-RUN] Estado actual '$mode'; se omitiría espera real de ${FALLBACK_TIMEOUT}s"
            break
        fi

        sleep "$step"
        elapsed=$((elapsed + step))
    done

    mode="$(detect_current_mode)"
    active_conn="$(get_active_connection)"
    ipv4="$(get_valid_ipv4_cidr || true)"
    state_code="$(get_device_state_code)"

    case "$mode" in
        HOME)
            log_msg "INFO" "Modo HOME activo y válido ($active_conn, IPv4: $ipv4). Se preserva conexión."
            return 0
            ;;
        MOBILE)
            log_msg "INFO" "Modo MOBILE activo y válido ($active_conn, IPv4: $ipv4). Se preserva conexión."
            return 0
            ;;
        NOMAD)
            log_msg "INFO" "Modo NOMAD ya activo ($active_conn, IPv4: $ipv4). Sin cambios."
            return 0
            ;;
        UNKNOWN)
            log_msg "WARN" "Conexión Wi-Fi desconocida activa ('$active_conn', IPv4: $ipv4). No se interrumpe ni se adopta como HOME/MOBILE."
            return 0
            ;;
    esac

    log_msg "INFO" "Sin conexión autorizada válida tras ${elapsed}s (estado=$state_code, ip=${ipv4:-none}). Activando respaldo NOMAD ('$AP_PROFILE')."
    activate_profile "$AP_PROFILE"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local final_mode final_ip
    final_mode="$(detect_current_mode)"
    final_ip="$(get_valid_ipv4_cidr || true)"
    if [[ "$final_mode" != "NOMAD" ]] || [[ "${final_ip%/*}" != "${AP_ADDRESS%/*}" ]]; then
        die "$EXIT_TRANSITION_FAILED" "El AP '$AP_PROFILE' no alcanzó estado NOMAD esperado (modo=$final_mode, ip=${final_ip:-none})"
    fi

    log_msg "INFO" "Modo NOMAD activado correctamente ($AP_PROFILE, IPv4: $final_ip)."
}

is_remote_session() {
    [[ -n "${SSH_CONNECTION:-}" ]] || [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]]
}

arm_remote_rollback() {
    local prev_profile="$1"
    local target_profile="$2"
    local rollback_sec="$3"

    resolve_state_dir
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    local state_file="$STATE_DIR/rollback.state"
    local self_path
    self_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_msg "INFO" "[DRY-RUN] Se guardaría estado previo '$prev_profile' y se programaría rollback en ${rollback_sec}s vía systemd-run."
        return 0
    fi

    command -v "$SYSTEMD_RUN_BIN" >/dev/null 2>&1 \
        || die "$EXIT_REMOTE_UNSAFE" "Sesión remota detectada sin systemd-run disponible para rollback seguro. Ejecuta localmente en consola."

    # Detener temporizador anterior si existiera
    "$SYSTEMCTL_BIN" stop dorsett-network-rollback.timer 2>/dev/null || true
    "$SYSTEMCTL_BIN" reset-failed dorsett-network-rollback.service dorsett-network-rollback.timer 2>/dev/null || true

    printf 'PREV_PROFILE=%s\nTARGET_PROFILE=%s\nTIMESTAMP=%s\n' \
        "$prev_profile" "$target_profile" "$(date '+%Y-%m-%dT%H:%M:%S')" > "$state_file"
    chmod 600 "$state_file"

    if ! "$SYSTEMD_RUN_BIN" \
        --unit=dorsett-network-rollback \
        --on-active="${rollback_sec}s" \
        --description="Dorsett automatic network rollback" \
        "$self_path" --config "$CONFIG_FILE" rollback >/dev/null 2>&1; then
        rm -f "$state_file"
        die "$EXIT_REMOTE_UNSAFE" "No se pudo programar el temporizador de rollback en systemd. Transición abortada por seguridad headless."
    fi

    log_msg "INFO" "Temporizador de reversión automática armado (${rollback_sec}s) hacia '${prev_profile:-fallback}'."
}

switch_mode_manual() {
    local mode_label="$1"
    local target_profile="$2"

    require_privileges
    acquire_lock
    check_dependencies

    local current_conn current_ip
    current_conn="$(get_active_connection)"
    current_ip="$(get_valid_ipv4_cidr || true)"

    if [[ "$current_conn" == "$target_profile" ]] && [[ -n "$current_ip" ]]; then
        log_msg "INFO" "El modo $mode_label ('$target_profile', IPv4: $current_ip) ya está activo. Sin cambios."
        return 0
    fi

    profile_exists "$target_profile" || die "$EXIT_PROFILE_MISSING" "El perfil '$target_profile' no existe. Ningún cambio aplicado."

    log_msg "WARN" "ATENCIÓN: cambiar a modo $mode_label ('$target_profile') puede desconectar sesiones SSH y WayVNC activas."

    local rollback_sec="${CUSTOM_ROLLBACK_SECONDS:-$ROLLBACK_TIMEOUT}"
    is_positive_int "$rollback_sec" || die "$EXIT_USAGE" "--rollback-seconds inválido: $rollback_sec"

    local remote=0
    if is_remote_session; then
        remote=1
    fi

    if [[ "$remote" -eq 1 ]]; then
        log_msg "INFO" "Sesión remota SSH detectada: exigiendo recuperación temporizada independiente de la sesión."
        arm_remote_rollback "$current_conn" "$target_profile" "$rollback_sec"
    elif [[ -n "$CUSTOM_ROLLBACK_SECONDS" ]]; then
        arm_remote_rollback "$current_conn" "$target_profile" "$rollback_sec"
    elif [[ "$FORCE_LOCAL" -eq 0 ]] && [[ "$DRY_RUN" -eq 0 ]]; then
        log_msg "INFO" "Consola local detectada (sin variables SSH). Ejecutando transición directa."
    fi

    activate_profile "$target_profile"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        local new_ip
        new_ip="$(get_valid_ipv4_cidr || echo 'sin IP aún')"
        log_msg "INFO" "Transición a modo $mode_label ('$target_profile', IPv4: $new_ip) completada."
        if [[ "$remote" -eq 1 ]] || [[ -n "$CUSTOM_ROLLBACK_SECONDS" ]]; then
            log_msg "INFO" "IMPORTANTE: verifica acceso desde un cliente y ejecuta 'dorsett-network confirm' antes de ${rollback_sec}s para cancelar la reversión automática."
        fi
    fi
}

cmd_confirm() {
    require_privileges
    acquire_lock
    resolve_state_dir
    local state_file="$STATE_DIR/rollback.state"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_msg "INFO" "[DRY-RUN] Se detendría dorsett-network-rollback.timer y se limpiaría $state_file"
        return 0
    fi

    if command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
        "$SYSTEMCTL_BIN" stop dorsett-network-rollback.timer 2>/dev/null || true
    fi
    rm -f "$state_file"
    log_msg "INFO" "Conectividad confirmada por el operador. Reversión automática cancelada."
}

cmd_rollback() {
    require_privileges
    acquire_lock
    check_dependencies
    resolve_state_dir
    local state_file="$STATE_DIR/rollback.state"
    local prev_profile=""

    if [[ -f "$state_file" ]]; then
        prev_profile="$(awk -F= '$1=="PREV_PROFILE"{sub(/^PREV_PROFILE=/,""); print; exit}' "$state_file")"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_msg "INFO" "[DRY-RUN] Se restauraría perfil previo '${prev_profile:-$HOME_PROFILE}'"
        return 0
    fi

    if [[ -n "$prev_profile" ]] && profile_exists "$prev_profile"; then
        log_msg "WARN" "Ejecutando rollback automático hacia el perfil previo '$prev_profile'..."
        if run_nmcli --wait "$NMCLI_TIMEOUT" connection up "$prev_profile" >/dev/null 2>&1; then
            rm -f "$state_file"
            log_msg "INFO" "Rollback completado: '$prev_profile' restaurado."
            return 0
        fi
        log_msg "ERROR" "No se pudo restaurar '$prev_profile'; intentando perfil doméstico '$HOME_PROFILE'."
    fi

    if profile_exists "$HOME_PROFILE"; then
        run_nmcli --wait "$NMCLI_TIMEOUT" connection up "$HOME_PROFILE" >/dev/null 2>&1 \
            && { rm -f "$state_file"; log_msg "INFO" "Rollback completado hacia '$HOME_PROFILE'."; return 0; }
    fi

    die "$EXIT_TRANSITION_FAILED" "Falló el rollback de red; se requiere inspección local."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                [[ $# -ge 2 ]] || die "$EXIT_USAGE" "--config requiere una ruta"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --rollback-seconds)
                [[ $# -ge 2 ]] || die "$EXIT_USAGE" "--rollback-seconds requiere un entero positivo"
                CUSTOM_ROLLBACK_SECONDS="$2"
                shift 2
                ;;
            --force-local)
                FORCE_LOCAL=1
                shift
                ;;
            -h|--help)
                COMMAND="help"
                shift
                ;;
            status|fallback|home|mobile|nomad|confirm|rollback|help)
                [[ -z "$COMMAND" ]] || die "$EXIT_USAGE" "Solo se permite un comando por ejecución"
                COMMAND="$1"
                shift
                ;;
            *)
                die "$EXIT_USAGE" "Argumento o comando desconocido: $1"
                ;;
        esac
    done

    [[ -n "$COMMAND" ]] || { usage; exit "$EXIT_USAGE"; }
}

main() {
    parse_args "$@"
    if [[ "$COMMAND" == "help" ]]; then
        usage
        exit "$EXIT_OK"
    fi

    load_config_file "$CONFIG_FILE"
    validate_config

    case "$COMMAND" in
        status) cmd_status ;;
        fallback) cmd_fallback ;;
        home) switch_mode_manual "HOME" "$HOME_PROFILE" ;;
        mobile) switch_mode_manual "MOBILE" "$MOBILE_PROFILE" ;;
        nomad) switch_mode_manual "NOMAD" "$AP_PROFILE" ;;
        confirm) cmd_confirm ;;
        rollback) cmd_rollback ;;
        *) die "$EXIT_USAGE" "Comando no soportado: $COMMAND" ;;
    esac
}

main "$@"
