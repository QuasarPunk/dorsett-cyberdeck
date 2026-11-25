# Auditoría Técnica del Sistema — 2026-11-24

- **Fecha de auditoría en hardware real:** 24 de noviembre de 2026.
- **Equipo auditado:** Raspberry Pi 5 (`raspi-ali`, arquitectura ARM64).
- **Naturaleza de este registro:** transcripción estructurada de la información técnica suministrada tras la auditoría ejecutada sobre la Raspberry Pi real. **Este documento no fue generado por ejecución directa de comandos desde la estación actual ni por el agente de IA sobre el host remoto.**
- **Política de sanitización:** en este archivo público se omiten secretos, direcciones MAC, UUID reales y se enmascaran los nombres personales de SSID domésticos/secundarios preservando los prefijos técnicos relevantes (por ejemplo, `netplan-wlan0-`).

---

## 1. Comandos de referencia ejecutados durante la auditoría

```bash
cat /etc/os-release
nmcli --version
systemctl is-active NetworkManager
nmcli device status
nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
nmcli connection show --active
ip -4 addr show wlan0
ip route
nmcli -f WIFI-PROPERTIES device show wlan0
iw dev
iw list
sudo ss -lntup
systemctl --user status wayvnc-lan.service --no-pager
systemctl is-active ssh smbd avahi-daemon
command -v dnsmasq
```

---

## 2. Sistema operativo

- **Distribución reportada en `/etc/os-release`:** Debian GNU/Linux 13 (`trixie`), versión completa `13.6`.
- **Arquitectura:** `ARM64`.
- **Hostname:** `raspi-ali`.
- **Observación metodológica:** la salida de `/etc/os-release` confirma Debian 13.6 como base, pero no permite concluir por sí sola si la imagen corresponde a Raspberry Pi OS o a una imagen Debian pura; el origen exacto de la imagen queda pendiente de verificación.

---

## 3. NetworkManager

- **Versión:** `1.52.1`.
- **Estado del servicio (`systemctl is-active NetworkManager`):** `active`.

---

## 4. Perfiles de conexión

| Perfil (sanitizado) | Tipo | Interfaz | Autoconexión | Prioridad | Estado en auditoría | Observaciones |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `netplan-wlan0-<HOME_SSID>` | Wi-Fi | `wlan0` | Habilitada | `100` | Activo | Perfil doméstico principal. Prefijo `netplan-` indica posible generación desde Netplan. |
| `<SECONDARY_WIFI_PROFILE>` | Wi-Fi | — | Habilitada | `0` | Inactivo | Perfil secundario 2.4 GHz existente; propósito y autorización pendientes de confirmar. |
| `netplan-eth0` | Ethernet | `eth0` | Habilitada | `0` | Inactivo | Prefijo `netplan-`; sin enlace Ethernet durante la auditoría. |
| `lo` | Loopback | `lo` | — | — | Presente | Interfaz local de bucle invertido. |

---

## 5. Interfaces

- **`wlan0`:** Wi-Fi, conectada y gestionada por NetworkManager.
- **`eth0`:** Ethernet, sin conexión física disponible durante la auditoría.
- **`lo`:** loopback.
- **`p2p-dev-wlan0`:** interfaz Wi-Fi P2P, desconectada.

---

## 6. Direccionamiento y parámetros de enlace (`wlan0`)

- **IPv4 observada:** `192.168.1.52/24`.
- **Método de asignación:** dinámica mediante DHCP.
- **Gateway por defecto:** `192.168.1.1`.
- **Métrica de ruta:** `600`.
- **Canal Wi-Fi observado:** `11`.
- **Frecuencia:** `2462 MHz`.
- **Ancho de canal:** `20 MHz`.
- **Nota sobre IP estable:** el usuario reporta que la IP doméstica se mantiene estable en `192.168.1.52`, aunque la existencia de una reserva DHCP en el router no fue comprobada directamente en esta auditoría.

---

## 7. Hardware inalámbrico y capacidades (`nmcli` e `iw list`)

### Capacidades declaradas por `nmcli` (`WIFI-PROPERTIES`)

- **Soportado:** WPA, WPA2, CCMP, Access Point (`AP`), Ad-hoc, banda `2.4 GHz`, banda `5 GHz`.
- **No soportado:** banda `6 GHz`, Mesh.

### Combinaciones válidas declaradas por `iw list`

- **Combinación 1:** hasta `2` interfaces `managed`, hasta `1` dispositivo P2P, hasta `1` `P2P-client` o `P2P-GO`, máximo total de `3` interfaces, hasta `2` canales.
- **Combinación 2:** hasta `1` interfaz `managed`, hasta `1` interfaz `AP`, hasta `1` `P2P-client`, hasta `1` `P2P-device`, máximo total de `4` interfaces, máximo de `1` canal compartido.
- **Evaluación:** el controlador declara soporte concurrente de `managed` + `AP` en un único canal compartido, pero la estabilidad de ese modo concurrente no ha sido probada experimentalmente.

---

## 8. Servicios y puertos activos

| Servicio | Estado | Puerto / Transporte | Escucha | Detalles observados |
| :--- | :--- | :--- | :--- | :--- |
| `ssh` | Activo | TCP `22` | `0.0.0.0` (IPv4) | Administración remota activa |
| `wayvnc-lan.service` (usuario) | Activo y habilitado | TCP `5901` | `0.0.0.0` (IPv4) | Unidad `~/.config/systemd/user/wayvnc-lan.service`; script `~/start-vnc.sh`; proceso `/usr/bin/wayvnc -r 0.0.0.0 5901`; activo desde `2026-11-07` |
| `wayvnc` (secundario) | Activo | TCP `5900` | — | Instancia adicional en ejecución; debe preservarse |
| `smbd` | Activo | TCP `445` | IPv4 e IPv6 | Directorio compartido reportado en `~/compartido` |
| `avahi-daemon` | Activo | mDNS | — | Resolución esperada vía `raspi-ali.local` |
| `dnsmasq` | Instalado | — | — | Ruta confirmada `/usr/sbin/dnsmasq`; no verificado aún bajo `ipv4.method shared` de NetworkManager |

---

## 9. Advertencias observadas

- En la salida de estado de `wayvnc-lan.service` se registró la advertencia:
  `Warning: ../src/output.c:300: Output NOOP-1 power state failure.`
- **Clasificación:** incidencia observada (`CONFIRMED`), no clasificada como fallo crítico. No modificar la configuración de WayVNC sin diagnóstico adicional específico.

---

## 10. Conclusiones

1. La plataforma base (`Debian 13.6 ARM64`, `NetworkManager 1.52.1`) dispone de todas las capacidades necesarias (`AP`, `WPA2/CCMP`, `dnsmasq`) para implementar el modo `NOMAD` mediante conmutación excluyente en `wlan0`.
2. Los servicios críticos (`ssh`, `wayvnc-lan.service` en `5901`, `wayvnc` en `5900`, `smbd`, `avahi-daemon`) se encuentran operativos y deben mantenerse intactos durante la evolución de red.
3. El prefijo `netplan-` en los perfiles de `NetworkManager` obliga a investigar `/etc/netplan/` antes de realizar modificaciones permanentes sobre perfiles existentes.
4. Por seguridad de enlace *headless* y falta de validación de concurrencia `STA+AP`, la versión `v0.4.0` debe operar exclusivamente por conmutación entre modo cliente y modo AP.

---

## 11. Acciones pendientes

1. Inspeccionar `/etc/netplan/` y `/etc/NetworkManager/system-connections/` para confirmar el origen y persistencia de los perfiles `netplan-*`.
2. Confirmar propósito y autorización del perfil Wi-Fi secundario de `2.4 GHz` (`autoconnect` habilitada, prioridad `0`).
3. Verificar `loginctl show-user` (estado real de `linger`), contenido de `~/start-vnc.sh`, configuración de autenticación de `WayVNC`, reglas de firewall activas y configuración de `Samba` (deshabilitación de SMB1 si estuviera presente).
4. Definir y registrar interactivamente el SSID/perfil del hotspot del Samsung Galaxy A10 (`MOBILE`, prioridad `50`), comprobando que no bloquee comunicación entre clientes.
5. Ejecutar la prueba controlada del perfil `Dorsett-AP` (`NOMAD`) con mecanismo de recuperación temporizada independiente de la sesión SSH antes de habilitar `dorsett-fallback.service`.
