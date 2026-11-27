#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

usage() {
    printf '%s\n' 'Uso: bash install.sh [--check | --help]' \
        '  --check  Comprueba plataforma, dependencias y wlan0 sin escribir archivos.' \
        '  --help   Muestra esta ayuda.' \
        '  Sin opciones: instala archivos con sudo y conserva la configuración local.'
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

case "$#" in
    0) mode=install ;;
    1)
        case "$1" in
            --check) mode=check ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    *) usage >&2; exit 2 ;;
esac

[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] \
    || die 'Se requiere Linux ARM64 (Debian 13 en Raspberry Pi 5).'
[[ -r /etc/os-release ]] || die 'No se puede identificar la distribución.'
. /etc/os-release
[[ "${ID:-}" == debian || "${ID_LIKE:-}" =~ (^|[[:space:]])debian($|[[:space:]]) ]] \
    || die 'Se requiere Debian 13 o un sistema basado en Debian 13.'
[[ "${VERSION_ID:-}" == 13 || "${VERSION_ID:-}" == 13.* ]] || die 'Se requiere la versión 13 de Debian.'

missing=()
for dependency in nmcli dnsmasq ip iw ss systemctl systemd-run journalctl loginctl \
    flock timeout install stat awk sed grep tr logger; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
done
[[ "${#missing[@]}" -eq 0 ]] || die "Faltan dependencias: ${missing[*]}"

systemctl is-active --quiet NetworkManager.service || die 'NetworkManager no está activo.'
ap_cap="$(timeout 10s nmcli -g WIFI-PROPERTIES.AP device show wlan0)" \
    || die 'No se pudo consultar wlan0 en NetworkManager.'
[[ "$ap_cap" == yes ]] || die 'wlan0 no declara soporte para modo AP.'
nmcli --version
printf 'Perfiles locales para identificar HOME y, si está registrado, MOBILE.\n'
PAGER=cat LC_ALL=C timeout 10s nmcli -f NAME,TYPE,DEVICE connection show \
    || die 'No se pudieron consultar los perfiles.'

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for source in software/scripts/{dorsett-network,setup-hotspot,collect-diagnostics}.sh \
    software/systemd/dorsett-fallback.service software/config/network.env.example; do
    [[ -f "$repo/$source" && -r "$repo/$source" ]] || die "Falta el archivo $source."
done

if [[ "$mode" == check ]]; then
    printf 'Comprobación previa completada.\n'
    exit 0
fi

[[ "$EUID" -eq 0 ]] || die 'Ejecuta sudo bash install.sh para instalar.'
exec 9>/run/dorsett-install.lock
flock -n 9 || die 'Ya hay otra instalación en curso.'

config_dir=/etc/dorsett
config="$config_dir/network.env"
[[ ! -L "$config_dir" && ! -L "$config" ]] || die 'La ruta de configuración contiene un enlace simbólico.'
if [[ -e "$config" ]]; then
    [[ -f "$config" && "$(stat -c '%u:%g:%a' "$config")" == 0:0:600 ]] \
        || die "$config debe ser un archivo regular root:root con permisos 0600."
fi

install -d -o root -g root -m 0755 "$config_dir"
install -D -T -o root -g root -m 0755 "$repo/software/scripts/dorsett-network.sh" /usr/local/bin/dorsett-network
install -D -T -o root -g root -m 0755 "$repo/software/scripts/setup-hotspot.sh" /usr/local/sbin/dorsett-setup-hotspot
install -D -T -o root -g root -m 0755 "$repo/software/scripts/collect-diagnostics.sh" /usr/local/bin/dorsett-collect-diagnostics
install -D -T -o root -g root -m 0644 "$repo/software/systemd/dorsett-fallback.service" /etc/systemd/system/dorsett-fallback.service
if [[ ! -e "$config" ]]; then
    install -o root -g root -m 0600 "$repo/software/config/network.env.example" "$config"
    printf 'Configuración creada. Ejecuta sudoedit %s para registrar el perfil HOME exacto.\n' "$config"
else
    printf 'Configuración conservada en %s.\n' "$config"
fi
systemctl daemon-reload
printf 'Instalación completada. Sigue docs/INSTALLATION.md para validar el AP antes de habilitar el fallback.\n'
