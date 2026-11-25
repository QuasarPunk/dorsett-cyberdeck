# Guía de Instalación Controlada y Recuperación — Dorsett v0.4.0

> **ADVERTENCIA DE SEGURIDAD OPERACIONAL:** este procedimiento está diseñado para ejecutarse sobre una Raspberry Pi 5 *headless*. **No habilites `dorsett-fallback.service` ni ejecutes transiciones de red en caliente sin haber verificado primero el mecanismo de recuperación y realizado las comprobaciones previas.**

---

## 1. Requisitos previos en la Raspberry Pi 5

Confirmado en auditoría del `2026-11-24`:

- Debian GNU/Linux 13 (`trixie`) ARM64.
- `NetworkManager` `1.52.1` activo.
- `dnsmasq` instalado (`/usr/sbin/dnsmasq`).
- `systemd`, `flock` (`util-linux`), `iproute2`, `iw`.

---

## 2. Comprobaciones previas (Solo lectura)

Antes de copiar scripts o crear el perfil AP, ejecuta en la Raspberry Pi:

1. **Capturar diagnóstico inicial sanitizado** (opcional desde copia local del repo):
   ```bash
   bash software/scripts/collect-diagnostics.sh
   ```
2. **Verificar Netplan vs NetworkManager** (imprescindible por el prefijo `netplan-` observado):
   ```bash
   ls -la /etc/netplan/
   sudo cat /etc/netplan/*.yaml 2>/dev/null || true
   nmcli -f NAME,UUID,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
   ```
3. **Verificar persistencia de WayVNC y reglas de firewall:**
   ```bash
   loginctl show-user "$USER" -p Linger
   sudo nft list ruleset 2>/dev/null || sudo iptables -L -n 2>/dev/null || true
   ```
4. **Confirmar que no hay conflicto con la subred `10.42.0.0/24`:**
   ```bash
   ip -4 addr show
   ip route
   ```

---

## 3. Instalación de archivos en rutas de sistema

No ejecutes `dorsett-fallback.service` apuntando directamente a scripts dentro de un directorio de usuario modificable. Instala copias propiedad de `root`:

```bash
sudo install -d -m 0755 /etc/dorsett
sudo install -m 0755 software/scripts/dorsett-network.sh /usr/local/bin/dorsett-network
sudo install -m 0755 software/scripts/setup-hotspot.sh /usr/local/sbin/dorsett-setup-hotspot
sudo install -m 0755 software/scripts/collect-diagnostics.sh /usr/local/bin/dorsett-collect-diagnostics
sudo install -m 0644 software/systemd/dorsett-fallback.service /etc/systemd/system/dorsett-fallback.service
sudo install -m 0600 software/config/network.env.example /etc/dorsett/network.env
```

---

## 4. Configuración de `/etc/dorsett/network.env`

Edita `/etc/dorsett/network.env` con los nombres exactos de los perfiles de tu Raspberry Pi (obtenidos con `nmcli -f NAME connection show`), manteniendo permisos estrictos (`0600`, propietario `root:root`):

```bash
sudo chown root:root /etc/dorsett/network.env
sudo chmod 0600 /etc/dorsett/network.env
sudo nano /etc/dorsett/network.env
```

Asegúrate de:

- Colocar entre comillas dobles los nombres con espacios (por ejemplo: `HOME_PROFILE="netplan-wlan0-MiRed"`).
- **No escribir contraseñas Wi-Fi** en `/etc/dorsett/network.env`.
- Verificar que `AP_ADDRESS=10.42.0.1/24`, `AP_BAND=bg`, `AP_CHANNEL=6` y `FALLBACK_TIMEOUT=30` corresponden a tu entorno.

---

## 5. Creación del perfil `Dorsett-AP` (sin activarlo todavía)

Ejecuta primero en modo simulación (`--dry-run`) y luego en modo real:

```bash
sudo /usr/local/sbin/dorsett-setup-hotspot --config /etc/dorsett/network.env --dry-run
sudo /usr/local/sbin/dorsett-setup-hotspot --config /etc/dorsett/network.env
```

El script:

- Verifica `NetworkManager`, `wlan0`, soporte AP y `dnsmasq`.
- Comprueba conflictos de subred y evita perfiles duplicados.
- Configura `802-11-wireless.mode ap`, `band bg`, `channel 6`, `ipv4.method shared`, `ipv4.addresses 10.42.0.1/24`, `ipv6.method disabled`, `connection.autoconnect no` y seguridad `WPA2-PSK` (`rsn` + `ccmp`).
- Solicita la contraseña WPA2 de forma interactiva oculta (mínimo 8 caracteres; recomendada >= 12 caracteres) sin exponerla en argumentos visibles.
- **No** activa el AP automáticamente al finalizar.

---

## 6. Prueba controlada del AP con recuperación temporizada (Obligatoria antes de habilitar el servicio)

Antes de habilitar `dorsett-fallback.service`, realiza la primera prueba manual del modo `NOMAD` con recuperación automática independiente de la sesión SSH.

### Cómo funciona la protección integrada en `dorsett-network`

Cuando ejecutas `sudo dorsett-network nomad` desde una sesión SSH:

1. El script detecta la sesión remota y registra el perfil actualmente activo (por ejemplo, `HOME_PROFILE`).
2. Programa un temporizador transitorio del sistema mediante `systemd-run --on-active=<ROLLBACK_TIMEOUT>s --unit=dorsett-network-rollback` (por defecto `120` segundos) que restaurará el perfil anterior aunque se corte la conexión SSH.
3. **Nunca** cancela el *rollback* automáticamente solo porque `wlan0` haya adquirido la IP `10.42.0.1`.
4. Activa `Dorsett-AP`.

### Pasos de verificación física

1. En la sesión SSH actual, verifica primero el estado sin cambios:
   ```bash
   dorsett-network --config /etc/dorsett/network.env status
   dorsett-network --config /etc/dorsett/network.env --dry-run nomad
   ```
2. Inicia la transición protegida (por ejemplo con ventana de 180 segundos para conectar la Tablet):
   ```bash
   sudo dorsett-network --config /etc/dorsett/network.env --rollback-seconds 180 nomad
   ```
3. Tu sesión SSH sobre la red doméstica se desconectará al cambiar `wlan0` a modo AP.
4. Desde la **Tablet X-View** o PC portátil:
   - Conéctate al Wi-Fi `Dorsett-AP` con la contraseña configurada.
   - Confirma que recibes IP por DHCP en `10.42.0.x`.
   - Conéctate por SSH a `10.42.0.1` (puerto `22`).
   - Prueba TightVNC en `10.42.0.1::5901` y Samba en `\\10.42.0.1`.
5. **Solo tras verificar acceso real desde un cliente**, cancela la reversión automática dentro de la sesión SSH en `10.42.0.1`:
   ```bash
   sudo dorsett-network --config /etc/dorsett/network.env confirm
   ```
6. Si algo falla y no logras conectarte al AP, espera a que expire el temporizador (`180s`): `systemd-run` ejecutará `dorsett-network rollback` y restaurará la red doméstica automáticamente.

---

## 7. Habilitación del servicio de arranque (`systemd`)

**Solo después** de completar satisfactoriamente la prueba manual del AP y verificar que el regreso a `HOME` funciona:

```bash
sudo systemctl daemon-reload
sudo systemctl enable dorsett-fallback.service
```

Para inspeccionar su ejecución tras un reinicio controlado:

```bash
systemctl status dorsett-fallback.service --no-pager
journalctl -u dorsett-fallback.service -b --no-pager
```
