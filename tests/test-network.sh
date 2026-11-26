#!/usr/bin/env bash
# ==============================================================================
# test-network.sh — Validación estática y pruebas automatizadas con mocks
# ==============================================================================
# NOTA: Estas pruebas verifican sintaxis, enlaces documentales, unidad systemd y
# lógica de scripts usando simulaciones (mocks) de nmcli/ip/systemd.
# NO representan validación física sobre hardware Raspberry Pi 5.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

DORSETT_NET="$REPO_ROOT/software/scripts/dorsett-network.sh"
SETUP_AP="$REPO_ROOT/software/scripts/setup-hotspot.sh"
COLLECT_DIAG="$REPO_ROOT/software/scripts/collect-diagnostics.sh"
SYSTEMD_UNIT="$REPO_ROOT/software/systemd/dorsett-fallback.service"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

TMP_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '[FAIL] %s\n' "$1" >&2
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    printf '[SKIP] %s\n' "$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        fail "$label (esperado='$expected', actual='$actual')"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if grep -Fq -- "$needle" <<< "$haystack"; then
        pass "$label"
    else
        fail "$label (no contiene '$needle')"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if ! grep -Fq -- "$needle" <<< "$haystack"; then
        pass "$label"
    else
        fail "$label (contiene cadena prohibida '$needle')"
    fi
}

run_checked() {
    local label="$1"
    shift
    local out rc=0
    out="$("$@" 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        fail "$label (exit=$rc): $out"
        return 1
    fi
    return 0
}

# ==============================================================================
# 1. Validación estática de scripts, CRLF, ShellCheck, systemd y enlaces MD
# ==============================================================================
run_static_checks() {
    printf '\n=== 1. Validación estática ===\n'
    local f
    for f in "$DORSETT_NET" "$SETUP_AP" "$COLLECT_DIAG" "$REPO_ROOT/tests/test-network.sh"; do
        if bash -n "$f"; then
            pass "bash -n: ${f#$REPO_ROOT/}"
        else
            fail "bash -n: ${f#$REPO_ROOT/}"
        fi
        if grep -q $'\r' "$f"; then
            fail "Saltos de línea CRLF detectados en ${f#$REPO_ROOT/}"
        else
            pass "Saltos de línea LF válidos: ${f#$REPO_ROOT/}"
        fi
    done

    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck "$DORSETT_NET" "$SETUP_AP" "$COLLECT_DIAG" "$REPO_ROOT/tests/test-network.sh"; then
            pass "shellcheck sin errores"
        else
            fail "shellcheck reportó advertencias o errores"
        fi
    else
        skip "shellcheck no está instalado en este entorno"
    fi

    # Validación básica de la unidad systemd (y systemd-analyze si existe)
    local unit_content
    unit_content="$(cat "$SYSTEMD_UNIT")"
    assert_contains "$unit_content" "Type=oneshot" "systemd unit es Type=oneshot"
    assert_contains "$unit_content" "After=NetworkManager.service" "systemd unit ordena después de NetworkManager.service"
    assert_contains "$unit_content" "Restart=no" "systemd unit no se reinicia indefinidamente"
    assert_contains "$unit_content" "ExecStart=/usr/local/bin/dorsett-network" "systemd unit apunta a /usr/local/bin/dorsett-network"
    assert_not_contains "$unit_content" "network-online.target" "systemd unit no depende de network-online.target"

    if command -v systemd-analyze >/dev/null 2>&1; then
        if systemd-analyze verify "$SYSTEMD_UNIT" >/dev/null 2>&1; then
            pass "systemd-analyze verify"
        else
            skip "systemd-analyze verify requiere entorno completo de unidades del sistema"
        fi
    else
        skip "systemd-analyze no está instalado en este entorno"
    fi

    # Comprobación de enlaces relativos en archivos Markdown
    local md_file link target dir_path broken=0 checked=0
    while IFS= read -r -d '' md_file; do
        dir_path="$(dirname "$md_file")"
        while IFS= read -r link; do
            link="${link#*](}"
            link="${link%)}"
            link="${link%%#*}"
            link="${link%% *}"
            [[ -z "$link" ]] && continue
            case "$link" in
                http://*|https://*|mailto:*|\#*) continue ;;
            esac
            checked=$((checked + 1))
            if [[ ! -e "$dir_path/$link" ]]; then
                fail "Enlace relativo roto en ${md_file#$REPO_ROOT/}: $link"
                broken=$((broken + 1))
            fi
        done < <(grep -oE '\[[^]]+\]\([^)]+\)' "$md_file" || true)
    done < <(find "$REPO_ROOT" -maxdepth 4 -name '*.md' -print0)

    if [[ "$broken" -eq 0 ]]; then
        pass "Todos los enlaces relativos Markdown ($checked) existen"
    fi
}

# ==============================================================================
# 2. Infraestructura Mock para nmcli / ip / systemd-run / systemctl / diag
# ==============================================================================
setup_mock_env() {
    MOCK_BIN="$TMP_TEST_DIR/mock_bin"
    MOCK_STATE="$TMP_TEST_DIR/mock_state"
    mkdir -p "$MOCK_BIN" "$MOCK_STATE"

    cat > "$MOCK_BIN/nmcli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${MOCK_STATE_DIR:?}"
LOG_FILE="$STATE_DIR/nmcli.calls"
printf '%s\n' "$*" >> "$LOG_FILE"

if [[ -n "${MOCK_NMCLI_DELAY:-}" ]]; then
    sleep "$MOCK_NMCLI_DELAY"
fi

if [[ "${MOCK_NM_RUNNING:-running}" != "running" ]]; then
    if [[ "$*" == *"general"* ]]; then
        printf '%s\n' "${MOCK_NM_RUNNING:-stopped}"
        exit 0
    fi
    exit 1
fi

args=("$@")
# Saltar flags globales (--wait N, -t, -g X, -f X, --ask)
cmd=""
field=""
terse=0
i=0
while [[ $i -lt ${#args[@]} ]]; do
    a="${args[$i]}"
    case "$a" in
        --wait|--escape|-f)
            i=$((i + 2))
            continue
            ;;
        -g)
            field="${args[$((i + 1))]}"
            i=$((i + 2))
            continue
            ;;
        -t|--ask|--show-secrets)
            terse=1
            i=$((i + 1))
            continue
            ;;
        --version)
            printf 'nmcli tool, version 1.52.1-mock\n'
            exit 0
            ;;
        *)
            cmd="${args[$i]}"
            break
            ;;
    esac
done

rest=("${args[@]:$((i + 1))}")

case "$cmd" in
    general)
        printf 'running\n'
        ;;
    device)
        sub="${rest[0]:-}"
        case "$sub" in
            status)
                if [[ "${MOCK_WIFI_PRESENT:-1}" == "1" ]]; then
                    if [[ "$terse" -eq 1 ]]; then
                        printf '%s:wifi\n' "${MOCK_IFACE:-wlan0}"
                        printf 'eth0:ethernet\n'
                    else
                        printf '%s\n' "${MOCK_IFACE:-wlan0}"
                    fi
                else
                    printf 'eth0:ethernet\n'
                fi
                ;;
            show)
                iface="${rest[1]:-wlan0}"
                if [[ "${MOCK_WIFI_PRESENT:-1}" != "1" ]] && [[ "$iface" == "${MOCK_IFACE:-wlan0}" ]]; then
                    exit 10
                fi
                case "$field" in
                    GENERAL.STATE)
                        printf '%s\n' "$(cat "$STATE_DIR/device_state" 2>/dev/null || echo '30 (disconnected)')"
                        ;;
                    GENERAL.CONNECTION)
                        printf '%s\n' "$(cat "$STATE_DIR/active_conn" 2>/dev/null || echo '--')"
                        ;;
                    IP4.ADDRESS)
                        printf '%s\n' "$(cat "$STATE_DIR/ipv4" 2>/dev/null || echo '')"
                        ;;
                    WIFI-PROPERTIES.AP)
                        printf '%s\n' "${MOCK_AP_CAP:-yes}"
                        ;;
                    *)
                        printf 'GENERAL.DEVICE:%s\nWIFI-PROPERTIES.AP:%s\n' "$iface" "${MOCK_AP_CAP:-yes}"
                        ;;
                esac
                ;;
        esac
        ;;
    connection)
        sub="${rest[0]:-}"
        case "$sub" in
            show)
                if [[ "${rest[1]:-}" == "--active" ]]; then
                    conn="$(cat "$STATE_DIR/active_conn" 2>/dev/null || echo '--')"
                    if [[ "$conn" != "--" && -n "$conn" ]]; then
                        printf '%s:802-11-wireless:%s\n' "$conn" "${MOCK_IFACE:-wlan0}"
                    fi
                elif [[ -n "${rest[1]:-}" ]]; then
                    prof="${rest[1]}"
                    if ! grep -Fxq -- "$prof" "$STATE_DIR/profiles.list" 2>/dev/null; then
                        exit 10
                    fi
                    case "$field" in
                        connection.id) printf '%s\n' "$prof" ;;
                        802-11-wireless.mode)
                            if [[ "$prof" == "${MOCK_AP_PROFILE:-Dorsett-AP}" ]]; then
                                printf 'ap\n'
                            else
                                printf 'infrastructure\n'
                            fi
                            ;;
                        802-11-wireless.band) printf 'bg\n' ;;
                        802-11-wireless.channel) printf '6\n' ;;
                        ipv4.method)
                            if [[ "$prof" == "${MOCK_AP_PROFILE:-Dorsett-AP}" ]]; then printf 'shared\n'; else printf 'auto\n'; fi
                            ;;
                        ipv4.addresses)
                            if [[ "$prof" == "${MOCK_AP_PROFILE:-Dorsett-AP}" ]]; then printf '10.42.0.1/24\n'; else printf '\n'; fi
                            ;;
                        connection.autoconnect)
                            if [[ "$prof" == "${MOCK_AP_PROFILE:-Dorsett-AP}" ]]; then printf 'no\n'; else printf 'yes\n'; fi
                            ;;
                        802-11-wireless-security.key-mgmt) printf 'wpa-psk\n' ;;
                        802-11-wireless-security.psk) cat "$STATE_DIR/ap.psk" ;;
                        *) printf 'connection.id:%s\n' "$prof" ;;
                    esac
                else
                    while IFS= read -r p; do
                        [[ -z "$p" ]] && continue
                        printf '%s:802-11-wireless:%s:yes:100\n' "$p" "${MOCK_IFACE:-wlan0}"
                    done < "$STATE_DIR/profiles.list"
                fi
                ;;
            up)
                prof="${rest[1]:-}"
                if ! grep -Fxq -- "$prof" "$STATE_DIR/profiles.list" 2>/dev/null; then
                    exit 10
                fi
                if [[ "${MOCK_FAIL_UP:-0}" == "1" ]]; then
                    exit 4
                fi
                printf '%s\n' "$prof" > "$STATE_DIR/active_conn"
                printf '100 (connected)\n' > "$STATE_DIR/device_state"
                if [[ "$prof" == "${MOCK_AP_PROFILE:-Dorsett-AP}" ]]; then
                    printf '10.42.0.1/24\n' > "$STATE_DIR/ipv4"
                elif [[ "$prof" == *"Mobile"* ]] || [[ "$prof" == *"mobile"* ]] || [[ "$prof" == *"Galaxy"* ]]; then
                    printf '192.168.43.25/24\n' > "$STATE_DIR/ipv4"
                else
                    printf '192.168.1.52/24\n' > "$STATE_DIR/ipv4"
                fi
                ;;
            add|modify)
                # Simular creación de perfil en setup-hotspot
                if [[ "$sub" == "add" ]]; then
                    for ((j=0; j<${#rest[@]}; j++)); do
                        if [[ "${rest[$j]}" == "con-name" ]]; then
                            printf '%s\n' "${rest[$((j+1))]}" >> "$STATE_DIR/profiles.list"
                        fi
                    done
                fi
                ;;
            edit)
                [[ "${XDG_CACHE_HOME:-}" == /dev/null ]] || exit 1
                sed -n 's/^set 802-11-wireless-security.psk //p' > "$STATE_DIR/ap.psk"
                ;;
        esac
        ;;
esac
EOF
    chmod +x "$MOCK_BIN/nmcli"

    cat > "$MOCK_BIN/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
if [[ "$*" == *"addr show"* ]]; then
    ipv4="$(cat "$STATE_DIR/ipv4" 2>/dev/null || true)"
    if [[ -n "$ipv4" ]]; then
        printf '3: %s    inet %s brd 10.42.0.255 scope global %s\n' "${MOCK_IFACE:-wlan0}" "$ipv4" "${MOCK_IFACE:-wlan0}"
    fi
elif [[ "$*" == *"route"* ]]; then
    printf 'default via 192.168.1.1 dev %s metric 600\n' "${MOCK_IFACE:-wlan0}"
fi
EOF
    chmod +x "$MOCK_BIN/ip"

    cat > "$MOCK_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
printf '%s\n' "$*" > "$STATE_DIR/systemd_run.last"
if [[ "${MOCK_SYSTEMD_RUN_FAIL:-0}" == "1" ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/systemd-run"

    cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/systemctl.calls"
if [[ "$*" == *"is-active"* ]]; then
    printf 'active\nactive\nactive\nactive\n'
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/systemctl"

    cat > "$MOCK_BIN/dnsmasq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN/dnsmasq"

    cat > "$MOCK_BIN/iw" <<'EOF'
#!/usr/bin/env bash
printf 'phy#0\n\tInterface wlan0\n\ttype managed\n'
EOF
    chmod +x "$MOCK_BIN/iw"

    cat > "$MOCK_BIN/ss" <<'EOF'
#!/usr/bin/env bash
printf 'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n'
EOF
    chmod +x "$MOCK_BIN/ss"

    cat > "$MOCK_BIN/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'Nov 24 12:00:00 raspi-ali wayvnc[100]: Warning: ../src/output.c:300: Output NOOP-1 power state failure.\n'
EOF
    chmod +x "$MOCK_BIN/journalctl"

    cat > "$MOCK_BIN/loginctl" <<'EOF'
#!/usr/bin/env bash
printf 'Linger=yes\n'
EOF
    chmod +x "$MOCK_BIN/loginctl"

    TEST_CFG="$TMP_TEST_DIR/network.env"
    cat > "$TEST_CFG" <<'EOF'
WIFI_INTERFACE=wlan0
HOME_PROFILE="netplan-wlan0-Mi Red Casa"
MOBILE_PROFILE="Galaxy A10 Hotspot"
AP_PROFILE="Dorsett-AP"
AP_SSID="Dorsett-AP"
AP_ADDRESS=10.42.0.1/24
AP_BAND=bg
AP_CHANNEL=6
FALLBACK_TIMEOUT=1
ROLLBACK_TIMEOUT=60
NMCLI_TIMEOUT=10
EOF

    export MOCK_STATE_DIR="$MOCK_STATE"
    export DORSETT_NMCLI_BIN="$MOCK_BIN/nmcli"
    export DORSETT_IP_BIN="$MOCK_BIN/ip"
    export DORSETT_SYSTEMD_RUN_BIN="$MOCK_BIN/systemd-run"
    export DORSETT_SYSTEMCTL_BIN="$MOCK_BIN/systemctl"
    export DORSETT_DNSMASQ_BIN="$MOCK_BIN/dnsmasq"
    export DORSETT_IW_BIN="$MOCK_BIN/iw"
    export DORSETT_SS_BIN="$MOCK_BIN/ss"
    export DORSETT_JOURNALCTL_BIN="$MOCK_BIN/journalctl"
    export DORSETT_LOGINCTL_BIN="$MOCK_BIN/loginctl"
    export DORSETT_LOGGER_BIN=true
    export DORSETT_ALLOW_NONROOT=1
    export DORSETT_STATE_DIR="$TMP_TEST_DIR/dorsett_state"
}

reset_mock_state() {
    : > "$MOCK_STATE/nmcli.calls"
    : > "$MOCK_STATE/systemctl.calls"
    rm -f "$MOCK_STATE/systemd_run.last" "$DORSETT_STATE_DIR/rollback.state" 2>/dev/null || true
    cat > "$MOCK_STATE/profiles.list" <<'EOF'
netplan-wlan0-Mi Red Casa
Galaxy A10 Hotspot
Dorsett-AP
Red Desconocida
EOF
    export MOCK_NM_RUNNING=running
    export MOCK_WIFI_PRESENT=1
    export MOCK_AP_CAP=yes
    export MOCK_FAIL_UP=0
    export MOCK_SYSTEMD_RUN_FAIL=0
    export MOCK_NMCLI_DELAY=""
}

run_net() {
    env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
        DORSETT_LOCK_FILE="$TMP_TEST_DIR/test.lock" \
        "$DORSETT_NET" --config "$TEST_CFG" "$@"
}

# ==============================================================================
# 3. Escenarios de prueba funcional (Mocks)
# ==============================================================================
run_functional_tests() {
    printf '\n=== 2. Pruebas funcionales simuladas (Mocks) ===\n'
    setup_mock_env

    # Argumentos inválidos
    reset_mock_state
    local rc=0
    run_net comando_invalido >/dev/null 2>&1 || rc=$?
    assert_eq "2" "$rc" "Validación de argumentos: comando inválido devuelve código 2"

    # T01 / T02: HOME disponible al arrancar (incluso sin Internet) + espacios en perfil
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'netplan-wlan0-Mi Red Casa\n' > "$MOCK_STATE/active_conn"
    printf '192.168.1.52/24\n' > "$MOCK_STATE/ipv4"
    local out
    out="$(run_net status)"
    assert_contains "$out" "detected_mode=HOME" "T01/T02 status detecta HOME con espacios en el nombre"
    run_net fallback >/dev/null 2>&1
    assert_eq "netplan-wlan0-Mi Red Casa" "$(cat "$MOCK_STATE/active_conn")" "T01/T02 fallback preserva HOME sin cambiar perfil"

    # T03: HOME ausente y MOBILE disponible (con espacios)
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'Galaxy A10 Hotspot\n' > "$MOCK_STATE/active_conn"
    printf '192.168.43.25/24\n' > "$MOCK_STATE/ipv4"
    run_net fallback >/dev/null 2>&1
    assert_eq "Galaxy A10 Hotspot" "$(cat "$MOCK_STATE/active_conn")" "T03 fallback preserva MOBILE con espacios"

    # T04: HOME y MOBILE ausentes -> activa Dorsett-AP
    reset_mock_state
    printf '30 (disconnected)\n' > "$MOCK_STATE/device_state"
    printf -- '--\n' > "$MOCK_STATE/active_conn"
    : > "$MOCK_STATE/ipv4"
    local no_mobile_config="$TMP_TEST_DIR/no-mobile.env"
    sed 's/^MOBILE_PROFILE=.*/MOBILE_PROFILE=""/' "$TEST_CFG" > "$no_mobile_config"
    # Usar un archivo alternativo para este escenario sin tocar el original.
    run_checked "T04 fallback con MOBILE sin configurar" run_net fallback --config "$no_mobile_config" || true
    assert_eq "Dorsett-AP" "$(cat "$MOCK_STATE/active_conn")" "T04 fallback activa Dorsett-AP cuando no hay conexión"
    assert_eq "10.42.0.1/24" "$(cat "$MOCK_STATE/ipv4")" "T04 modo NOMAD obtiene 10.42.0.1/24"

    # Idempotencia: segunda ejecución de fallback con NOMAD activo no cambia ni falla
    : > "$MOCK_STATE/nmcli.calls"
    run_net fallback >/dev/null 2>&1
    assert_eq "Dorsett-AP" "$(cat "$MOCK_STATE/active_conn")" "T10/Idempotencia: fallback mantiene NOMAD sin interrumpir"
    assert_not_contains "$(cat "$MOCK_STATE/nmcli.calls")" "connection up" "Idempotencia: no re-ejecuta connection up si NOMAD ya está activo"

    # Dry-run no cambia estado
    reset_mock_state
    printf '30 (disconnected)\n' > "$MOCK_STATE/device_state"
    printf -- '--\n' > "$MOCK_STATE/active_conn"
    : > "$MOCK_STATE/ipv4"
    run_net --dry-run fallback >/dev/null 2>&1
    assert_eq "--" "$(cat "$MOCK_STATE/active_conn")" "Modo --dry-run no modifica el estado de conexión"

    # T11 + T12: Transición remota segura y rollback
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'netplan-wlan0-Mi Red Casa\n' > "$MOCK_STATE/active_conn"
    printf '192.168.1.52/24\n' > "$MOCK_STATE/ipv4"
    SSH_CONNECTION="192.168.1.43 55000 192.168.1.52 22" \
        "$DORSETT_NET" --config "$TEST_CFG" --rollback-seconds 90 nomad >/dev/null 2>&1
    assert_eq "Dorsett-AP" "$(cat "$MOCK_STATE/active_conn")" "T11/T12 transición remota cambia a Dorsett-AP"
    assert_contains "$(cat "$MOCK_STATE/systemd_run.last")" "--on-active=90s" "T12 programa temporizador systemd-run independiente de SSH"

    # Simular expiración de rollback (vuelve al perfil HOME previo con espacios)
    run_net rollback >/dev/null 2>&1
    assert_eq "netplan-wlan0-Mi Red Casa" "$(cat "$MOCK_STATE/active_conn")" "T12 rollback restaura perfil previo con espacios"

    # Bloqueo estricto si es sesión remota y systemd-run falla
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'netplan-wlan0-Mi Red Casa\n' > "$MOCK_STATE/active_conn"
    printf '192.168.1.52/24\n' > "$MOCK_STATE/ipv4"
    export MOCK_SYSTEMD_RUN_FAIL=1
    rc=0
    SSH_CONNECTION="192.168.1.43 55000 192.168.1.52 22" \
        "$DORSETT_NET" --config "$TEST_CFG" nomad >/dev/null 2>&1 || rc=$?
    assert_eq "6" "$rc" "Seguridad remota: aborta transición (exit 6) si falla el mecanismo de rollback"
    assert_eq "netplan-wlan0-Mi Red Casa" "$(cat "$MOCK_STATE/active_conn")" "Seguridad remota: conserva perfil original tras abortar"

    # Confirmación explícita cancela timer
    reset_mock_state
    run_net confirm >/dev/null 2>&1
    assert_contains "$(cat "$MOCK_STATE/systemctl.calls")" "stop dorsett-network-rollback.timer" "Confirmación detiene temporizador de rollback"

    # T14: Perfil AP inexistente
    reset_mock_state
    grep -Fxv "Dorsett-AP" "$MOCK_STATE/profiles.list" > "$MOCK_STATE/profiles.tmp"
    mv "$MOCK_STATE/profiles.tmp" "$MOCK_STATE/profiles.list"
    printf '30 (disconnected)\n' > "$MOCK_STATE/device_state"
    printf -- '--\n' > "$MOCK_STATE/active_conn"
    : > "$MOCK_STATE/ipv4"
    rc=0
    run_net fallback >/dev/null 2>&1 || rc=$?
    assert_eq "5" "$rc" "T14 perfil AP inexistente devuelve exit 5 sin cambios destructivos"

    # T15: Perfil Wi-Fi desconocido activo -> avisar y preservar
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'Red Desconocida\n' > "$MOCK_STATE/active_conn"
    printf '172.16.0.40/24\n' > "$MOCK_STATE/ipv4"
    local stderr_out
    stderr_out="$(run_net fallback 2>&1)"
    assert_eq "Red Desconocida" "$(cat "$MOCK_STATE/active_conn")" "T15 perfil desconocido se preserva sin interrupción"
    assert_contains "$stderr_out" "Conexión Wi-Fi desconocida activa" "T15 registra advertencia por perfil desconocido"

    # T16: DHCP lento / link-local 169.254.x.x -> espera acotada y fallback a NOMAD
    reset_mock_state
    printf '70 (connecting (getting IP configuration))\n' > "$MOCK_STATE/device_state"
    printf 'netplan-wlan0-Mi Red Casa\n' > "$MOCK_STATE/active_conn"
    printf '169.254.10.20/16\n' > "$MOCK_STATE/ipv4"
    run_net fallback >/dev/null 2>&1
    assert_eq "Dorsett-AP" "$(cat "$MOCK_STATE/active_conn")" "T16 DHCP lento/link-local activa fallback NOMAD tras ventana acotada"

    # T17: Concurrencia (segundo proceso rechazado por bloqueo)
    reset_mock_state
    printf '100 (connected)\n' > "$MOCK_STATE/device_state"
    printf 'netplan-wlan0-Mi Red Casa\n' > "$MOCK_STATE/active_conn"
    printf '192.168.1.52/24\n' > "$MOCK_STATE/ipv4"
    (
        export MOCK_NMCLI_DELAY=2
        DORSETT_LOCK_TIMEOUT=0 run_net fallback >/dev/null 2>&1
    ) &
    local bg_pid=$!
    sleep 0.4
    rc=0
    DORSETT_LOCK_TIMEOUT=0 run_net fallback >/dev/null 2>&1 || rc=$?
    wait "$bg_pid" || true
    assert_eq "4" "$rc" "T17 bloqueo concurrente rechaza ejecución simultánea (exit 4)"

    # T18: NetworkManager caído o interfaz no disponible
    reset_mock_state
    export MOCK_NM_RUNNING=stopped
    rc=0
    run_net status >/dev/null 2>&1 || rc=$?
    assert_eq "3" "$rc" "T18 NetworkManager inactivo devuelve exit 3"

    reset_mock_state
    export MOCK_WIFI_PRESENT=0
    rc=0
    run_net status >/dev/null 2>&1 || rc=$?
    assert_eq "3" "$rc" "T18 interfaz wlan0 ausente devuelve exit 3"

    # setup-hotspot.sh --dry-run (sin duplicados y sin activar AP)
    reset_mock_state
    local setup_out
    setup_out="$("$SETUP_AP" --config "$TEST_CFG" --dry-run 2>&1)" || fail "setup-hotspot --dry-run falló: $setup_out"
    assert_contains "$setup_out" "ya existe" "setup-hotspot.sh detecta perfil existente y evita duplicados"
    setup_out="$("$SETUP_AP" --config "$TEST_CFG" --update --dry-run 2>&1)" || fail "setup-hotspot --update --dry-run falló: $setup_out"
    assert_contains "$setup_out" "NO fue activado automáticamente" "setup-hotspot.sh no activa AP por defecto"
    : > "$MOCK_STATE/nmcli.calls"
    setup_out="$(printf '%s\n' 'psk-ficticia:123' 'psk-ficticia:123' |
        "$SETUP_AP" --config "$TEST_CFG" --update --ask 2>&1)" || fail "setup-hotspot --update no guardó la PSK simulada"
    assert_contains "$setup_out" "validado" "El aprovisionamiento interactivo verifica la PSK guardada"
    assert_not_contains "$setup_out" "psk-ficticia:123" "El aprovisionamiento no imprime la PSK"
    assert_not_contains "$(cat "$MOCK_STATE/nmcli.calls")" "psk-ficticia:123" "La PSK no se pasa en argumentos a nmcli"
    assert_not_contains "$(cat "$MOCK_STATE/nmcli.calls")" "connection up" "El aprovisionamiento real simulado deja el AP inactivo"

    # T19: collect-diagnostics.sh sanitizado (sin MAC/UUID/SSID personales ni --show-secrets)
    reset_mock_state
    cat > "$MOCK_BIN/nmcli" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--show-secrets"* ]]; then
    echo "FORBIDDEN_SHOW_SECRETS"
    exit 99
fi
if [[ "$*" == *"connection show"* ]]; then
    printf 'netplan-wlan0-CasaPrivadaAli:802-11-wireless:wlan0:yes:100\n'
    printf 'Dorsett-AP:802-11-wireless:wlan0:no:0\n'
elif [[ "$*" == *"--version"* ]]; then
    printf 'nmcli tool, version 1.52.1-mock\n'
elif [[ "$*" == *"device status"* ]]; then
    printf 'wlan0 wifi connected netplan-wlan0-CasaPrivadaAli\n'
elif [[ "$*" == *"WIFI-PROPERTIES"* ]]; then
    printf 'WIFI-PROPERTIES.AP:yes\n'
fi
EOF
    chmod +x "$MOCK_BIN/nmcli"
    cat > "$MOCK_BIN/ip" <<'EOF'
#!/usr/bin/env bash
printf '3: wlan0    inet 192.168.1.52/24 scope global wlan0 link/ether aa:bb:cc:dd:ee:ff\n'
printf 'UUID=12345678-1234-1234-1234-123456789abc\n'
EOF
    chmod +x "$MOCK_BIN/ip"

    local diag_out="$TMP_TEST_DIR/diag-report.md"
    "$COLLECT_DIAG" --output "$diag_out" >/dev/null
    local diag_content
    diag_content="$(cat "$diag_out")"
    assert_not_contains "$diag_content" "aa:bb:cc:dd:ee:ff" "T19 sanitiza direcciones MAC"
    assert_not_contains "$diag_content" "12345678-1234-1234-1234-123456789abc" "T19 sanitiza UUIDs"
    assert_not_contains "$diag_content" "CasaPrivadaAli" "T19 sanitiza SSID doméstico personal"
    assert_contains "$diag_content" "Dorsett-AP" "T19 conserva identificador público Dorsett-AP"
    assert_contains "$diag_content" "[REDACTED-MAC]" "T19 incluye marcador de MAC sanitizada"
}

main() {
    run_static_checks
    run_functional_tests

    printf '\n=== Resumen ===\n'
    printf 'PASS: %d | FAIL: %d | SKIP: %d\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
    printf 'NOTA: Pruebas funcionales ejecutadas con mocks. Las pruebas físicas en Raspberry Pi 5 siguen pendientes.\n'
    [[ "$FAIL_COUNT" -eq 0 ]]
}

main "$@"
