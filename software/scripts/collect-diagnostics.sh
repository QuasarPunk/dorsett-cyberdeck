#!/usr/bin/env bash
# ==============================================================================
# collect-diagnostics.sh — Recopilación sanitizada de diagnósticos (Solo lectura)
# ==============================================================================
# Genera un informe Markdown fechado sin ejecutar cambios en el sistema,
# sin usar --show-secrets y sin exponer credenciales ni identificadores sensibles
# en el modo sanitizado por defecto.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

OUTPUT_PATH=""
PRIVATE_MODE=0
WIFI_INTERFACE="${DORSETT_WIFI_INTERFACE:-wlan0}"
AP_PROFILE="${DORSETT_AP_PROFILE:-Dorsett-AP}"

NMCLI_BIN="${DORSETT_NMCLI_BIN:-nmcli}"
IP_BIN="${DORSETT_IP_BIN:-ip}"
IW_BIN="${DORSETT_IW_BIN:-iw}"
SS_BIN="${DORSETT_SS_BIN:-ss}"
SYSTEMCTL_BIN="${DORSETT_SYSTEMCTL_BIN:-systemctl}"
JOURNALCTL_BIN="${DORSETT_JOURNALCTL_BIN:-journalctl}"
LOGINCTL_BIN="${DORSETT_LOGINCTL_BIN:-loginctl}"
DNSMASQ_BIN="${DORSETT_DNSMASQ_BIN:-dnsmasq}"

CONFIRMED_COUNT=0
ISSUE_COUNT=0
SUMMARY_NOTES=()

usage() {
    cat <<'EOF'
Uso: collect-diagnostics.sh [OPCIONES]

Recopila información de sistema, red y servicios en modo solo lectura
y genera un informe Markdown fechado.

Opciones:
  --output <ruta>    Ruta exacta del informe Markdown a generar.
  --interface <if>   Interfaz Wi-Fi a inspeccionar (por defecto wlan0).
  --private          Desactiva el enmascaramiento de MAC/UUID/SSID personales
                     (NUNCA incluye contraseñas ni --show-secrets).
  -h, --help         Muestra esta ayuda.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                [[ $# -ge 2 ]] || { usage >&2; exit 2; }
                OUTPUT_PATH="$2"
                shift 2
                ;;
            --interface)
                [[ $# -ge 2 ]] || { usage >&2; exit 2; }
                WIFI_INTERFACE="$2"
                shift 2
                ;;
            --private)
                PRIVATE_MODE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Opción desconocida: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

resolve_default_output() {
    if [[ -n "$OUTPUT_PATH" ]]; then
        return 0
    fi
    local script_dir repo_root out_dir ts
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd -- "$script_dir/../.." 2>/dev/null && pwd || pwd)"
    if [[ -d "$repo_root/docs/audits" ]] && [[ -w "$repo_root/docs/audits" ]]; then
        out_dir="$repo_root/docs/audits/local"
    else
        out_dir="${TMPDIR:-/tmp}/dorsett-diagnostics"
    fi
    mkdir -p "$out_dir"
    ts="$(date '+%Y%m%d-%H%M%S')"
    OUTPUT_PATH="$out_dir/diagnostics-$ts.md"
}

sanitize_stream() {
    if [[ "$PRIVATE_MODE" -eq 1 ]]; then
        cat
        return 0
    fi

    sed -E \
        -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/[REDACTED-MAC]/g' \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[REDACTED-UUID]/g' \
        -e 's/(netplan-wlan0-)[^:|[:space:]]+/\1[REDACTED-SSID]/g' \
        -e 's/(SSID:[[:space:]]*).*/\1[REDACTED-SSID]/g'
}

sanitize_nm_profiles() {
    if [[ "$PRIVATE_MODE" -eq 1 ]]; then
        cat
        return 0
    fi

    awk -F: -v ap="$AP_PROFILE" '
    {
        name=$1
        if (name ~ /^netplan-wlan0-/) {
            $1="netplan-wlan0-[REDACTED-SSID]"
        } else if (name != "" && name != ap && name != "lo" && name != "netplan-eth0" && $2 ~ /wireless|wifi/) {
            $1="[REDACTED-WIFI-PROFILE]"
        }
        OFS=":"; print
    }' | sanitize_stream
}

record_section() {
    local title="$1"
    local cmd_label="$2"
    shift 2
    local output rc=0

    printf '## %s\n\n' "$title"
    printf '`Comando:` `%s`\n\n' "$cmd_label"

    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
        CONFIRMED_COUNT=$((CONFIRMED_COUNT + 1))
        printf -- '- Estado: `CONFIRMED`\n\n```text\n%s\n```\n\n' "$(printf '%s\n' "$output" | sanitize_stream)"
    else
        ISSUE_COUNT=$((ISSUE_COUNT + 1))
        if grep -qiE 'permission denied|operation not permitted|not authorized|requires root' <<< "$output"; then
            SUMMARY_NOTES+=("$title: requiere privilegios adicionales")
            printf -- '- Estado: `PRIVILEGE_REQUIRED` (código %d)\n\n```text\n%s\n```\n\n' "$rc" "$(printf '%s\n' "$output" | sanitize_stream)"
        else
            SUMMARY_NOTES+=("$title: error de recopilación (código $rc)")
            printf -- '- Estado: `COLLECTION_ERROR` (código %d)\n\n```text\n%s\n```\n\n' "$rc" "$(printf '%s\n' "$output" | sanitize_stream)"
        fi
    fi
}

record_unavailable() {
    local title="$1"
    local reason="$2"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    SUMMARY_NOTES+=("$title: $reason")
    printf '## %s\n\n- Estado: `UNAVAILABLE`\n- Motivo: %s\n\n' "$title" "$reason"
}

collect_firewall_readonly() {
    if command -v ufw >/dev/null 2>&1; then
        ufw status verbose 2>&1 || return $?
        return 0
    elif command -v nft >/dev/null 2>&1; then
        nft list ruleset 2>&1 || return $?
        return 0
    elif command -v iptables >/dev/null 2>&1; then
        iptables -L -n -v 2>&1 || return $?
        return 0
    fi
    printf 'No se detectaron herramientas ufw, nft ni iptables en PATH.\n'
    return 0
}

check_dnsmasq_readonly() {
    command -v "$DNSMASQ_BIN" 2>/dev/null || ls -l /usr/sbin/dnsmasq
}

collect_hw_model() {
    if [[ -r /proc/device-tree/model ]]; then
        tr -d '\0' < /proc/device-tree/model
        printf '\n'
    else
        uname -m
    fi
}

main() {
    parse_args "$@"
    resolve_default_output
    mkdir -p "$(dirname -- "$OUTPUT_PATH")"

    local body_file
    body_file="$(mktemp)"
    trap 'rm -f "${body_file:-}"' EXIT

    {
        record_section "Sistema operativo" "cat /etc/os-release" cat /etc/os-release
        record_section "Kernel y arquitectura" "uname -srm" uname -srm
        record_section "Modelo de hardware" "/proc/device-tree/model" collect_hw_model

        if command -v "$NMCLI_BIN" >/dev/null 2>&1; then
            record_section "Versión de NetworkManager" "nmcli --version" "$NMCLI_BIN" --version
            record_section "Estado de interfaces" "nmcli device status" "$NMCLI_BIN" device status
            printf '## Perfiles y prioridades (sin secretos)\n\n'
            printf '`Comando:` `nmcli -t -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show`\n\n'
            local prof_out prof_rc=0
            set +e
            prof_out="$("$NMCLI_BIN" -t -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show 2>&1)"
            prof_rc=$?
            set -e
            if [[ "$prof_rc" -eq 0 ]]; then
                CONFIRMED_COUNT=$((CONFIRMED_COUNT + 1))
                printf -- '- Estado: `CONFIRMED`\n\n```text\n%s\n```\n\n' "$(printf '%s\n' "$prof_out" | sanitize_nm_profiles)"
            else
                ISSUE_COUNT=$((ISSUE_COUNT + 1))
                SUMMARY_NOTES+=("Perfiles NetworkManager: error código $prof_rc")
                printf -- '- Estado: `COLLECTION_ERROR` (%d)\n\n```text\n%s\n```\n\n' "$prof_rc" "$prof_out"
            fi

            record_section "Conexiones activas" "nmcli -f NAME,TYPE,DEVICE connection show --active" "$NMCLI_BIN" -f NAME,TYPE,DEVICE connection show --active
            record_section "Propiedades Wi-Fi ($WIFI_INTERFACE)" "nmcli -f WIFI-PROPERTIES device show $WIFI_INTERFACE" "$NMCLI_BIN" -f WIFI-PROPERTIES device show "$WIFI_INTERFACE"
        else
            record_unavailable "NetworkManager / nmcli" "No se encontró el binario $NMCLI_BIN"
        fi

        if command -v "$IP_BIN" >/dev/null 2>&1; then
            record_section "Direcciones IPv4" "ip -4 addr show" "$IP_BIN" -4 addr show
            record_section "Tabla de rutas" "ip route" "$IP_BIN" route
        else
            record_unavailable "Direccionamiento IP" "No se encontró el binario $IP_BIN"
        fi

        if command -v "$IW_BIN" >/dev/null 2>&1; then
            record_section "Interfaces inalámbricas" "iw dev" "$IW_BIN" dev
            record_section "Capacidades y combinaciones inalámbricas" "iw list" "$IW_BIN" list
        else
            record_unavailable "Capacidades inalámbricas (iw)" "No se encontró el binario $IW_BIN"
        fi

        if command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
            record_section "Servicios base (NetworkManager, ssh, smbd, avahi-daemon)" "systemctl is-active" "$SYSTEMCTL_BIN" is-active NetworkManager ssh smbd avahi-daemon
            record_section "Estado del servicio WayVNC LAN (usuario)" "systemctl --user status wayvnc-lan.service --no-pager" "$SYSTEMCTL_BIN" --user status wayvnc-lan.service --no-pager
            record_section "Estado del servicio dorsett-fallback" "systemctl status dorsett-fallback.service --no-pager" "$SYSTEMCTL_BIN" status dorsett-fallback.service --no-pager
        else
            record_unavailable "Servicios systemd" "No se encontró $SYSTEMCTL_BIN"
        fi

        if command -v "$SS_BIN" >/dev/null 2>&1; then
            record_section "Puertos en escucha" "ss -lntup" "$SS_BIN" -lntup
        else
            record_unavailable "Puertos en escucha" "No se encontró $SS_BIN"
        fi

        if command -v "$DNSMASQ_BIN" >/dev/null 2>&1 || [[ -x /usr/sbin/dnsmasq ]]; then
            record_section "Disponibilidad de dnsmasq" "command -v dnsmasq / /usr/sbin/dnsmasq" check_dnsmasq_readonly
        else
            record_unavailable "dnsmasq" "No instalado o no encontrado en /usr/sbin/dnsmasq"
        fi

        if command -v "$LOGINCTL_BIN" >/dev/null 2>&1; then
            record_section "Estado de persistencia de usuario (linger)" "loginctl show-user -p Linger" "$LOGINCTL_BIN" show-user "${USER:-}" -p Linger
        else
            record_unavailable "loginctl linger" "No se encontró $LOGINCTL_BIN"
        fi

        if command -v "$JOURNALCTL_BIN" >/dev/null 2>&1; then
            record_section "Advertencias recientes de servicios" "journalctl -p warning -n 30 --no-pager" "$JOURNALCTL_BIN" -p warning -n 30 --no-pager
        else
            record_unavailable "Advertencias recientes (journalctl)" "No se encontró $JOURNALCTL_BIN"
        fi

        record_section "Estado del firewall (solo lectura)" "ufw/nft/iptables" collect_firewall_readonly
    } > "$body_file"

    {
        printf '# Informe de Diagnóstico del Sistema — Proyecto Dorsett\n\n'
        printf -- '- **Fecha y hora:** %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf -- '- **Modo de salida:** %s (sin secretos ni `--show-secrets`)\n' "$([[ "$PRIVATE_MODE" -eq 1 ]] && echo 'PRIVADO' || echo 'SANITIZADO')"
        printf -- '- **Secciones confirmadas:** %d\n' "$CONFIRMED_COUNT"
        printf -- '- **Secciones con error, ausencia o privilegios insuficientes:** %d\n\n' "$ISSUE_COUNT"
        printf '## Resumen\n\n'
        if [[ "${#SUMMARY_NOTES[@]}" -eq 0 ]]; then
            printf -- '- Todas las comprobaciones se recopilaron sin incidencias de acceso.\n\n'
        else
            local note
            for note in "${SUMMARY_NOTES[@]}"; do
                printf -- '- %s\n' "$note"
            done
            printf '\n'
        fi
        cat "$body_file"
    } > "$OUTPUT_PATH"

    printf 'Informe generado en: %s\n' "$OUTPUT_PATH"
}

main "$@"
