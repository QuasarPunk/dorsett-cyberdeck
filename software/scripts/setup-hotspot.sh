#!/usr/bin/env bash
# ==============================================================================
# setup-hotspot.sh — Aprovisionamiento seguro del perfil Dorsett-AP (NOMAD)
# ==============================================================================
# Crea o actualiza el perfil de Access Point en NetworkManager sin activarlo
# automáticamente por defecto.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

readonly EXIT_OK=0
readonly EXIT_GENERAL=1
readonly EXIT_USAGE=2
readonly EXIT_PREREQ=3
readonly EXIT_CONFLICT=4
readonly EXIT_PRIVILEGE=5

CONFIG_FILE="${DORSETT_CONFIG:-/etc/dorsett/network.env}"
WIFI_INTERFACE="wlan0"
AP_PROFILE="Dorsett-AP"
AP_SSID="Dorsett-AP"
AP_ADDRESS="10.42.0.1/24"
AP_BAND="bg"
AP_CHANNEL="6"
AP_WPS_METHOD="1"
NMCLI_TIMEOUT="20"

DRY_RUN=0
UPDATE_EXISTING=0
ACTIVATE_AFTER=0

NMCLI_BIN="${DORSETT_NMCLI_BIN:-nmcli}"
IP_BIN="${DORSETT_IP_BIN:-ip}"
DNSMASQ_BIN="${DORSETT_DNSMASQ_BIN:-dnsmasq}"

log_msg() {
    local level="$1"
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

die() {
    local code="$1"
    shift
    log_msg "ERROR" "$*"
    exit "$code"
}

usage() {
    cat <<'EOF'
Uso: setup-hotspot.sh [OPCIONES]

Crea o actualiza el perfil Access Point (Dorsett-AP) en NetworkManager
sin activarlo automáticamente por defecto.

Opciones:
  --config <ruta>    Ruta a network.env (por defecto /etc/dorsett/network.env).
  --update           Actualiza el perfil existente si ya existe en NetworkManager.
  --ask              Solicita la contraseña de forma interactiva (comportamiento predeterminado).
  --activate         Activa el AP al finalizar mediante dorsett-network (requiere protección remota).
  --dry-run          Simula validaciones y comandos sin modificar NetworkManager.
  -h, --help         Muestra esta ayuda.
EOF
}

load_config_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    [[ -r "$path" ]] || die "$EXIT_PRIVILEGE" "No se puede leer configuración: $path"

    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            if [[ "$val" =~ ^\"(.*)\"$ ]]; then
                val="${BASH_REMATCH[1]}"
            elif [[ "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            case "$key" in
                WIFI_INTERFACE) WIFI_INTERFACE="$val" ;;
                AP_PROFILE) AP_PROFILE="$val" ;;
                AP_SSID) AP_SSID="$val" ;;
                AP_ADDRESS) AP_ADDRESS="$val" ;;
                AP_BAND) AP_BAND="$val" ;;
                AP_CHANNEL) AP_CHANNEL="$val" ;;
                NMCLI_TIMEOUT) NMCLI_TIMEOUT="$val" ;;
            esac
        fi
    done < "$path"
}

run_nmcli() {
    if command -v timeout >/dev/null 2>&1; then
        LC_ALL=C timeout "$NMCLI_TIMEOUT" "$NMCLI_BIN" "$@"
    else
        LC_ALL=C "$NMCLI_BIN" "$@"
    fi
}

check_prerequisites() {
    if [[ "$DRY_RUN" -eq 0 ]] && [[ "${DORSETT_ALLOW_NONROOT:-0}" != "1" ]] && [[ "$EUID" -ne 0 ]]; then
        die "$EXIT_PRIVILEGE" "Este script requiere privilegios de root (sudo) para crear perfiles de sistema."
    fi

    command -v "$NMCLI_BIN" >/dev/null 2>&1 || die "$EXIT_PREREQ" "No se encontró nmcli"
    local nm_state
    nm_state="$(run_nmcli -t -f RUNNING general 2>/dev/null || true)"
    [[ "$nm_state" == "running" ]] || die "$EXIT_PREREQ" "NetworkManager no está activo"

    run_nmcli -t -f DEVICE device status 2>/dev/null | awk -F: -v iface="$WIFI_INTERFACE" '$1 == iface {found=1} END{exit !found}' \
        || die "$EXIT_PREREQ" "Interfaz $WIFI_INTERFACE no detectada en NetworkManager"

    local ap_cap
    ap_cap="$(run_nmcli -g WIFI-PROPERTIES.AP device show "$WIFI_INTERFACE" 2>/dev/null | head -n1 || true)"
    [[ "$ap_cap" == "yes" ]] || die "$EXIT_PREREQ" "El adaptador $WIFI_INTERFACE no declara soporte Access Point (WIFI-PROPERTIES.AP=$ap_cap)"

    if ! command -v "$DNSMASQ_BIN" >/dev/null 2>&1 && [[ ! -x /usr/sbin/dnsmasq ]]; then
        die "$EXIT_PREREQ" "dnsmasq no está instalado (requerido para ipv4.method shared). No se instala automáticamente."
    fi
}

check_subnet_conflict() {
    local ap_ip="${AP_ADDRESS%/*}"
    local ap_prefix="${ap_ip%.*}."
    local line iface cidr

    if ! command -v "$IP_BIN" >/dev/null 2>&1; then
        log_msg "WARN" "Comando ip no disponible; se omite verificación local de conflictos de subred."
        return 0
    fi

    while IFS= read -r line; do
        iface="$(awk '{print $2}' <<< "$line")"
        cidr="$(awk '{print $4}' <<< "$line")"
        [[ "$iface" == "$WIFI_INTERFACE" ]] && continue
        if [[ "$cidr" == "${ap_prefix}"* ]]; then
            die "$EXIT_CONFLICT" "Conflicto de subred detectado en interfaz '$iface' ($cidr colisiona con $AP_ADDRESS)"
        fi
    done < <("$IP_BIN" -4 -o addr show 2>/dev/null || true)
}

prompt_wpa_passphrase() {
    local psk1 psk2
    while true; do
        IFS= read -r -s -p "Ingresa contraseña WPA2-PSK para '$AP_SSID' (mín. 8 caracteres, rec. >=12): " psk1 || return 1
        printf '\n' >&2
        if [[ "${#psk1}" -lt 8 ]] || [[ "${#psk1}" -gt 63 ]]; then
            log_msg "WARN" "La contraseña debe tener entre 8 y 63 caracteres."
            continue
        fi
        IFS= read -r -s -p "Confirma la contraseña WPA2-PSK: " psk2 || return 1
        printf '\n' >&2
        if [[ "$psk1" != "$psk2" ]]; then
            log_msg "WARN" "Las contraseñas no coinciden. Intenta nuevamente."
            continue
        fi
        if [[ "${#psk1}" -lt 12 ]]; then
            log_msg "WARN" "Contraseña aceptada, aunque se recomienda usar al menos 12 caracteres."
        fi
        printf '%s' "$psk1"
        return 0
    done
}

apply_ap_security_stdin() (
    set +x
    local psk saved_psk
    psk="$(prompt_wpa_passphrase)" || die "$EXIT_GENERAL" "Entrada de contraseña cancelada. Reintenta con --update."
    # nmcli guarda el historial del editor bajo XDG_CACHE_HOME.
    if ! printf 'set 802-11-wireless-security.key-mgmt wpa-psk\nset 802-11-wireless-security.proto rsn\nset 802-11-wireless-security.pairwise ccmp\nset 802-11-wireless-security.group ccmp\nset 802-11-wireless-security.psk %s\nsave\nquit\n' "$psk" \
        | XDG_CACHE_HOME=/dev/null run_nmcli connection edit "$AP_PROFILE" >/dev/null 2>&1; then
        die "$EXIT_GENERAL" "Falló el guardado de la seguridad WPA2. Reintenta con --update."
    fi
    saved_psk="$(run_nmcli --show-secrets --escape no -g 802-11-wireless-security.psk connection show "$AP_PROFILE" 2>/dev/null)" \
        || die "$EXIT_GENERAL" "No se pudo verificar la contraseña guardada. Reintenta con --update."
    [[ "$saved_psk" == "$psk" ]] \
        || die "$EXIT_GENERAL" "La contraseña guardada difiere de la ingresada. Reintenta con --update y evita espacios al inicio o al final."
)

configure_profile() {
    local exists=0
    if run_nmcli -g connection.id connection show "$AP_PROFILE" >/dev/null 2>&1; then
        exists=1
    fi

    if [[ "$exists" -eq 1 ]] && [[ "$UPDATE_EXISTING" -eq 0 ]]; then
        log_msg "INFO" "El perfil '$AP_PROFILE' ya existe. No se crean duplicados (usa --update si deseas reconfigurarlo)."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_msg "INFO" "[DRY-RUN] Se aplicaría wps-method=$AP_WPS_METHOD (WPS deshabilitado) al perfil existente"
        else
            run_nmcli connection modify "$AP_PROFILE" \
                802-11-wireless-security.wps-method "$AP_WPS_METHOD" >/dev/null
            validate_final_profile
            ( set +x
              saved_psk="$(run_nmcli --show-secrets -g 802-11-wireless-security.psk connection show "$AP_PROFILE" 2>/dev/null)" \
                  && [[ -n "$saved_psk" && "$saved_psk" != '--' ]]
            ) || die "$EXIT_GENERAL" "El perfil existente carece de una contraseña verificable. Usa --update."
        fi
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$exists" -eq 0 ]]; then
            log_msg "INFO" "[DRY-RUN] Se crearía perfil Wi-Fi '$AP_PROFILE' (SSID='$AP_SSID', ifname='$WIFI_INTERFACE')"
        else
            log_msg "INFO" "[DRY-RUN] Se actualizaría perfil existente '$AP_PROFILE'"
        fi
        log_msg "INFO" "[DRY-RUN] Parámetros: mode=ap band=$AP_BAND channel=$AP_CHANNEL ipv4.method=shared ipv4.addresses=$AP_ADDRESS ipv6.method=disabled autoconnect=no security=wpa-psk/rsn/ccmp wps-method=$AP_WPS_METHOD (deshabilitado)"
        return 0
    fi

    if [[ "$exists" -eq 0 ]]; then
        run_nmcli connection add \
            type wifi \
            ifname "$WIFI_INTERFACE" \
            con-name "$AP_PROFILE" \
            autoconnect no \
            ssid "$AP_SSID" >/dev/null
    fi

    run_nmcli connection modify "$AP_PROFILE" \
        connection.interface-name "$WIFI_INTERFACE" \
        connection.autoconnect no \
        802-11-wireless.ssid "$AP_SSID" \
        802-11-wireless.mode ap \
        802-11-wireless.band "$AP_BAND" \
        802-11-wireless.channel "$AP_CHANNEL" \
        ipv4.method shared \
        ipv4.addresses "$AP_ADDRESS" \
        ipv6.method disabled \
        802-11-wireless-security.wps-method "$AP_WPS_METHOD" >/dev/null

    apply_ap_security_stdin

    validate_final_profile
}

validate_final_profile() {
    local mode band chan ipv4_m ipv4_a autoconn key_mgmt wps_method wps_value
    mode="$(run_nmcli -g 802-11-wireless.mode connection show "$AP_PROFILE")"
    band="$(run_nmcli -g 802-11-wireless.band connection show "$AP_PROFILE")"
    chan="$(run_nmcli -g 802-11-wireless.channel connection show "$AP_PROFILE")"
    ipv4_m="$(run_nmcli -g ipv4.method connection show "$AP_PROFILE")"
    ipv4_a="$(run_nmcli -g ipv4.addresses connection show "$AP_PROFILE")"
    autoconn="$(run_nmcli -g connection.autoconnect connection show "$AP_PROFILE")"
    key_mgmt="$(run_nmcli -g 802-11-wireless-security.key-mgmt connection show "$AP_PROFILE")"
    wps_method="$(run_nmcli -g 802-11-wireless-security.wps-method connection show "$AP_PROFILE")"
    wps_value="${wps_method%% *}"

    [[ "$mode" == "ap" ]] || die "$EXIT_GENERAL" "Validación fallida: mode=$mode (esperado ap)"
    [[ "$ipv4_m" == "shared" ]] || die "$EXIT_GENERAL" "Validación fallida: ipv4.method=$ipv4_m (esperado shared)"
    [[ "$autoconn" == "no" ]] || die "$EXIT_GENERAL" "Validación fallida: autoconnect=$autoconn (esperado no)"
    [[ "$key_mgmt" == "wpa-psk" ]] || die "$EXIT_GENERAL" "Validación fallida: key-mgmt=$key_mgmt (esperado wpa-psk)"
    [[ "$wps_value" == "$AP_WPS_METHOD" ]] || die "$EXIT_GENERAL" "Validación fallida: wps-method=$wps_method (esperado $AP_WPS_METHOD / deshabilitado)"

    log_msg "INFO" "Perfil '$AP_PROFILE' validado: mode=$mode band=$band channel=$chan ipv4=$ipv4_a ($ipv4_m) autoconnect=$autoconn security=$key_mgmt wps-method=$wps_method"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                [[ $# -ge 2 ]] || die "$EXIT_USAGE" "--config requiere ruta"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --update)
                UPDATE_EXISTING=1
                shift
                ;;
            --ask)
                shift
                ;;
            --activate)
                ACTIVATE_AFTER=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage
                exit "$EXIT_OK"
                ;;
            *)
                die "$EXIT_USAGE" "Opción desconocida: $1"
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    load_config_file "$CONFIG_FILE"
    check_prerequisites
    check_subnet_conflict
    configure_profile

    if [[ "$ACTIVATE_AFTER" -eq 1 ]]; then
        local script_dir helper
        script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        if command -v dorsett-network >/dev/null 2>&1; then
            helper="dorsett-network"
        else
            helper="$script_dir/dorsett-network.sh"
        fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_msg "INFO" "[DRY-RUN] Se activaría el AP mediante: $helper --config $CONFIG_FILE nomad"
        else
            "$helper" --config "$CONFIG_FILE" nomad
        fi
    else
        log_msg "INFO" "El perfil '$AP_PROFILE' NO fue activado automáticamente."
        log_msg "INFO" "Para probarlo con recuperación segura ejecuta: sudo dorsett-network --config $CONFIG_FILE nomad"
    fi
}

main "$@"
