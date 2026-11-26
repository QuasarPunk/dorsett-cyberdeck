# Memoria Técnica Permanente — Proyecto Dorsett

Este documento constituye la memoria técnica viva del **Proyecto Dorsett** (`dorsett-cyberdeck`, ecosistema **QuasarPunk**). Su objetivo es permitir que cualquier desarrollador o agente de IA comprenda el estado real, la arquitectura y las incógnitas del sistema sin depender de conversaciones previas.

> **Política de sanitización pública:** esta memoria técnica no almacena contraseñas, claves PSK, claves privadas SSH, direcciones MAC personales, UUID reales de perfiles ni nombres personales de redes domésticas o secundarias. Dichos valores locales deben residir únicamente en el sistema objetivo (`/etc/dorsett/network.env` o perfiles protegidos de `NetworkManager`), excluidos de Git.

---

## Convención de estados

Cada dato técnico significativo se etiqueta explícitamente con uno de los siguientes estados:

- **`CONFIRMED`**: verificado mediante salida real del sistema en la auditoría del `2026-11-24`.
- **`REPORTED`**: informado por el propietario o por documentación previa del repositorio sin verificación directa por comandos recientes.
- **`IMPLEMENTED`**: desarrollado en el repositorio (`v0.4.0`), pendiente de despliegue y validación física en la Raspberry Pi.
- **`PLANNED`**: previsto para etapas futuras del proyecto.
- **`UNKNOWN`**: información todavía no disponible o no inspeccionada.

---

## 1. Identidad y propósito

- **Nombre del proyecto:** Proyecto Dorsett (`dorsett-cyberdeck`) [`CONFIRMED` — contexto del proyecto].
- **Organización:** QuasarPunk [`CONFIRMED` — contexto del proyecto].
- **Propósito:** CyberDeck modular basada en Raspberry Pi 5 orientada a soberanía tecnológica, operación *offline-first*, administración remota *headless*, almacenamiento NAS local, nodo central de telemetría/control para robótica e IoT (**GreenNode**, robótica móvil, mecatrónica) y futura plataforma de IA local (**Scio**) [`REPORTED` / `PLANNED`].
- **Idioma:** documentación en español; identificadores de software en inglés [`CONFIRMED` — convención del proyecto].

---

## 2. Inventario de hardware

| Componente | Especificación | Rol | Estado | Procedencia / Fecha |
| :--- | :--- | :--- | :--- | :--- |
| **SBC principal** | Raspberry Pi 5 (`ARM64`) | Cómputo central, servidor *headless* y NAS | `CONFIRMED` | Auditoría `2026-11-24` |
| **Pantalla / Terminal** | Tablet X-View Quantum Carbono (Windows 8.1 32-bit) | Terminal táctil vía TightVNC Viewer y cliente SMB | `REPORTED` | README / reporte `2026-11-24` |
| **Teclado** | Teclado ultracompacto Noga | Entrada principal de texto | `REPORTED` | README / reporte `2026-11-24` |
| **Mouse** | Mouse óptico Noga | Dispositivo apuntador | `REPORTED` | README / reporte `2026-11-24` |
| **Smartphone** | Samsung Galaxy A10 | Hotspot móvil (`MOBILE`) y cliente LAN | `REPORTED` | Reporte `2026-11-24` |
| **Estación de desarrollo** | PC de escritorio (Windows) | Desarrollo, SSH, VNC y gestión del repositorio | `REPORTED` | Reporte `2026-11-24` |
| **Coprocesador I/O** | Arduino UNO | Futuras funciones de entrada/salida y sensores | `PLANNED` | Reporte `2026-11-24` |
| **Alimentación portátil** | Banco de baterías / gestión de energía | Autonomía eléctrica móvil | `PLANNED` | README / Roadmap |

---

## 3. Sistema operativo y versiones

| Parámetro | Valor observado | Estado | Fecha / Procedencia |
| :--- | :--- | :--- | :--- |
| **Sistema operativo** | Debian GNU/Linux 13 (`trixie`), versión `13.6` | `CONFIRMED` | `/etc/os-release` (`2026-11-24`) |
| **Origen exacto de imagen** | Derivado o imagen base Debian / Raspberry Pi OS por confirmar | `UNKNOWN` | No concluir Raspberry Pi OS solo por `/etc/os-release` (`2026-11-24`) |
| **Arquitectura** | `ARM64` | `CONFIRMED` | Auditoría `2026-11-24` |
| **Hostname** | `raspi-ali` | `CONFIRMED` | Auditoría `2026-11-24` |
| **Gestor de red** | `NetworkManager` `1.52.1` (activo) | `CONFIRMED` | `nmcli --version`, `systemctl is-active` (`2026-11-24`) |
| **Entorno gráfico** | Wayland / `labwc` | `REPORTED` | Documentación previa (`README.md`) |

---

## 4. Arquitectura de software

- **Capa base (operativa en host):** Debian 13.6 ARM64 + `systemd` + `NetworkManager 1.52.1` [`CONFIRMED`, `2026-11-24`].
- **Capa de acceso remoto y archivos (operativa en host):** OpenSSH (`ssh`), `WayVNC` en TCP `5900` y `5901` (`wayvnc-lan.service` de usuario), Samba (`smbd`) y `avahi-daemon` [`CONFIRMED`, `2026-11-24`].
- **Capa de conectividad autónoma `v0.4.0` (en repositorio):**
  - `software/scripts/dorsett-network.sh` — CLI para consultar estado, ejecutar *fallback* al arranque y realizar conmutaciones controladas [`IMPLEMENTED`, `2026-11-24`].
  - `software/scripts/setup-hotspot.sh` — aprovisionamiento seguro del perfil `Dorsett-AP` sin activarlo automáticamente [`IMPLEMENTED`, `2026-11-24`].
  - `software/scripts/collect-diagnostics.sh` — recolección sanitizada de estado en solo lectura [`IMPLEMENTED`, `2026-11-24`].
  - `software/systemd/dorsett-fallback.service` — unidad *oneshot* de sistema tras `NetworkManager.service` [`IMPLEMENTED`, `2026-11-24`].
  - `software/config/network.env.example` — plantilla de variables externas [`IMPLEMENTED`, `2026-11-24`].

---

## 5. Interfaces de red

Estado observado mediante `nmcli device status` e `ip` el `2026-11-24`:

| Interfaz | Tipo | Estado observado | Notas | Estado |
| :--- | :--- | :--- | :--- | :--- |
| `wlan0` | Wi-Fi | Conectada y gestionada por NetworkManager (`192.168.1.52/24`, gw `192.168.1.1`, métrica `600`) | Canal `11`, `2462 MHz`, ancho `20 MHz` | `CONFIRMED` |
| `eth0` | Ethernet | Sin conexión disponible durante la auditoría | Perfil `netplan-eth0` inactivo | `CONFIRMED` |
| `lo` | Loopback | Activa | Gestionada / perfil `lo` presente | `CONFIRMED` |
| `p2p-dev-wlan0` | Wi-Fi P2P | Desconectada | Interfaz virtual P2P | `CONFIRMED` |

---

## 6. Capacidades del controlador inalámbrico (`wlan0`)

### Propiedades (`nmcli -f WIFI-PROPERTIES device show wlan0`) — `CONFIRMED` (`2026-11-24`)

- **Seguridad soportada:** WPA, WPA2, CCMP.
- **Modos soportados:** Access Point (`AP`), Ad-hoc.
- **Bandas soportadas:** 2.4 GHz, 5 GHz.
- **No soportado:** banda 6 GHz, Mesh.

### Combinaciones válidas (`iw list`) — `CONFIRMED` (`2026-11-24`)

- **Combinación 1:** hasta 2 interfaces `managed`, hasta 1 dispositivo P2P, hasta 1 `P2P-client` o `P2P-GO`, máximo 3 interfaces totales, hasta 2 canales.
- **Combinación 2:** hasta 1 interfaz `managed`, hasta 1 interfaz `AP`, hasta 1 `P2P-client`, hasta 1 `P2P-device`, máximo 4 interfaces totales, máximo **1 canal compartido**.
- **Nota técnica:** aunque el controlador declara concurrencia cliente + AP en un mismo canal, su estabilidad no ha sido validada experimentalmente. Por decisión arquitectónica ([ADR-001](decisions/ADR-001-network-modes.md)), Dorsett `v0.4.0` usa exclusivamente **conmutación excluyente** entre modo cliente y modo AP.

---

## 7. Perfiles de conexión

### Perfiles existentes en el sistema (`2026-11-24`)

| Perfil (sanitizado en doc pública) | Tipo | Interfaz | Autoconexión | Prioridad | Estado en auditoría | Estado |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `netplan-wlan0-<HOME_SSID>` *(perfil doméstico autorizado)* | Wi-Fi | `wlan0` | Habilitada | `100` | Activo (`192.168.1.52/24`, DHCP) | `CONFIRMED` |
| `<SECONDARY_WIFI_PROFILE>` *(perfil secundario 2.4 GHz existente)* | Wi-Fi | — | Habilitada | `0` | Inactivo; propósito y autorización pendientes de confirmar | `CONFIRMED` (existencia) / `UNKNOWN` (autorización) |
| `netplan-eth0` | Ethernet | `eth0` | Habilitada | `0` | Inactivo | `CONFIRMED` |
| `lo` | Loopback | `lo` | — | — | Presente | `CONFIRMED` |

> **Observación crítica sobre Netplan:** los perfiles principales llevan el prefijo `netplan-`. Antes de modificar o eliminar perfiles permanentes en la Raspberry Pi, se debe inspeccionar `/etc/netplan/` y `/run/NetworkManager/system-connections/` para confirmar el origen y la persistencia de estos perfiles.

### Perfiles oficiales del diseño `v0.4.0`

| Modo | Nombre de perfil | Rol | Autoconexión / Prioridad | Estado |
| :--- | :--- | :--- | :--- | :--- |
| `HOME` | Configurado en `HOME_PROFILE` (`/etc/dorsett/network.env`) | Cliente Wi-Fi doméstico | Sí / `100` | `CONFIRMED` en host (pendiente integración env) |
| `MOBILE` | Configurado en `MOBILE_PROFILE` (hotspot Galaxy A10) | Cliente Wi-Fi móvil | Sí / `50` | `PLANNED` / `UNKNOWN` (SSID real pendiente) |
| `NOMAD` | `Dorsett-AP` (SSID `Dorsett-AP`) | Access Point (`10.42.0.1/24`, `shared`) | No / N/A | `IMPLEMENTED` en `setup-hotspot.sh`, no creado en Pi |

---

## 8. Servicios y puertos

| Servicio / Unidad | Puerto / Escucha | Estado observado (`2026-11-24`) | Notas | Estado |
| :--- | :--- | :--- | :--- | :--- |
| `ssh` | TCP `22` (`0.0.0.0`) | Activo | Acceso remoto por terminal | `CONFIRMED` |
| `wayvnc-lan.service` (usuario) | TCP `5901` (`0.0.0.0`) | Activo y habilitado (en ejecución desde `2026-11-07`) | Comando observado: `/usr/bin/wayvnc -r 0.0.0.0 5901` | `CONFIRMED` |
| `wayvnc` (instancia secundaria) | TCP `5900` | Activo | Debe preservarse sin alteraciones | `CONFIRMED` |
| `smbd` (Samba) | TCP `445` (IPv4 e IPv6) | Activo | Comparte `~/compartido` (`REPORTED`) | `CONFIRMED` (servicio) / `REPORTED` (ruta) |
| `avahi-daemon` | mDNS | Activo | Resolución esperada `raspi-ali.local` | `CONFIRMED` (daemon) / `UNKNOWN` (resolución AP) |
| `NetworkManager` | D-Bus / control de red | Activo (`1.52.1`) | Gestor exclusivo de conectividad | `CONFIRMED` |
| `dorsett-fallback.service` | N/A (`oneshot`) | Definido en `software/systemd/` | No instalado ni habilitado en la Pi | `IMPLEMENTED` |

---

## 9. Rutas de archivos relevantes

### En la Raspberry Pi (sistema objetivo)

- `~/.config/systemd/user/wayvnc-lan.service` — unidad systemd de usuario para WayVNC LAN [`CONFIRMED`, `2026-11-24`].
- `~/start-vnc.sh` — script de arranque de WayVNC LAN (contenido exacto no inspeccionado) [`CONFIRMED` existencia / `UNKNOWN` contenido].
- `~/compartido` (reportado como `/home/ali/compartido`) — carpeta compartida por Samba [`REPORTED`].
- `/usr/sbin/dnsmasq` — binario de `dnsmasq` instalado [`CONFIRMED`, `2026-11-24`].
- `/etc/os-release` — identificación del sistema base [`CONFIRMED`, `2026-11-24`].

### Rutas previstas para despliegue controlado (`v0.4.0`) — `IMPLEMENTED` / no desplegadas aún

`bash install.sh --check` comprueba los requisitos de la Pi. `sudo bash install.sh` instala las copias de sistema y conserva el contenido de `network.env` en actualizaciones. El propietario registra HOME con el nombre exacto y puede dejar `MOBILE_PROFILE=""`. El aprovisionamiento de NOMAD guarda la PSK en NetworkManager con el historial del editor bloqueado. La habilitación del fallback queda para después de la prueba manual. [Procedimiento de despliegue](INSTALLATION.md)

- `/usr/local/bin/dorsett-network`
- `/usr/local/sbin/dorsett-setup-hotspot`
- `/usr/local/bin/dorsett-collect-diagnostics` *(opcional recomendado)*
- `/etc/dorsett/network.env` (`root:root`, `0600`)
- `/etc/systemd/system/dorsett-fallback.service`

---

## 10. Dependencias instaladas

- `NetworkManager` (`1.52.1`) [`CONFIRMED`].
- `dnsmasq` (`/usr/sbin/dnsmasq`) [`CONFIRMED`, funcionamiento con `ipv4.method shared` aún no verificado].
- `openssh-server` (`ssh`), `samba` (`smbd`), `avahi-daemon`, `wayvnc`, `iw`, `iproute2` (`ip`, `ss`) [`CONFIRMED`].
- `shellcheck` / herramientas adicionales de validación: no verificadas en la Raspberry Pi [`UNKNOWN`].

---

## 11. Configuraciones conocidas

- Perfil doméstico con DHCP en `wlan0`, IP observada `192.168.1.52/24`, gateway `192.168.1.1`, métrica `600`, prioridad `100` [`CONFIRMED`].
- Reserva DHCP estática en el router para `192.168.1.52`: reportada por el usuario como IP estable, pero reserva en router no comprobada directamente [`REPORTED` / `UNKNOWN`].
- Persistencia de sesión de usuario mediante `loginctl enable-linger` para `wayvnc-lan.service`: informada en `README.md` previo, pendiente de verificación directa [`REPORTED` / `UNKNOWN`].
- Dirección propuesta del modo `NOMAD`: `10.42.0.1/24` con `ipv4.method shared`, canal `6` (`2.4 GHz`, banda `bg`), WPA2-PSK/CCMP, `autoconnect=no`, IPv6 deshabilitado [`IMPLEMENTED` en `setup-hotspot.sh`].

---

## 12. Particularidades del entorno gráfico

- El entorno gráfico se ejecuta sobre **Wayland / `labwc`** [`REPORTED`].
- Existen **dos instancias de `WayVNC`**: una en TCP `5900` y otra dedicada en TCP `5901` (`-r 0.0.0.0 5901`) para compatibilidad con TightVNC Viewer en la Tablet X-View con Windows 8.1 de 32 bits [`CONFIRMED` puertos/proceso / `REPORTED` motivo de compatibilidad].
- Se observó la advertencia en WayVNC:
  `Warning: ../src/output.c:300: Output NOOP-1 power state failure.` [`CONFIRMED`].

---

## 13. Problemas conocidos

1. **Advertencia `Output NOOP-1 power state failure` en WayVNC:** registrada como incidencia observada (`CONFIRMED`), sin evidencia de fallo crítico en operación; no modificar WayVNC sin diagnóstico previo.
2. **Prefijo `netplan-` en perfiles de NetworkManager:** riesgo de sobrescritura o duplicación si se edita Netplan y NetworkManager simultáneamente sin determinar el origen [`CONFIRMED` prefijo / `UNKNOWN` configuración `/etc/netplan`].
3. **Perfil secundario 2.4 GHz con autoconexión habilitada:** su propósito y autorización no están confirmados (`UNKNOWN`); podría competir si el perfil doméstico no está disponible.
4. **Windows 8.1 de 32 bits en la Tablet X-View:** sistema operativo sin soporte regular de seguridad; requiere precauciones de aislamiento de red y compatibilidad de cifrado/autenticación en VNC y SMB [`REPORTED`].
5. **Ausencia de alimentación portátil:** `v0.4.0` resuelve la autonomía de red (`NOMAD`), no la autonomía energética por baterías [`REPORTED`].

---

## 14. Decisiones técnicas vigentes

- **ADR-001 ([docs/decisions/ADR-001-network-modes.md](decisions/ADR-001-network-modes.md)):**
  - `NetworkManager` es el único gestor de conexiones.
  - Arquitectura en tres modos (`HOME`, `MOBILE`, `NOMAD`).
  - Conmutación excluyente cliente/AP en `wlan0` (sin concurrencia STA+AP en `v0.4.0`).
  - Uso de `ipv4.method shared` (`10.42.0.1/24`) aprovechando `dnsmasq` vía NetworkManager.
  - *Fallback* limitado al arranque en `v0.4.0` (sin retorno automático desde `NOMAD` hacia `HOME` para evitar cortar sesiones VNC/SSH activas).
  - Ninguna dependencia de Internet para validar conectividad local.

---

## 15. Información pendiente de verificar (`UNKNOWN`)

- Contenido de `/etc/netplan/*.yaml` y archivos en `/etc/NetworkManager/system-connections/` o `/run/NetworkManager/`.
- Origen exacto de la imagen del sistema operativo (Debian puro vs Raspberry Pi OS base).
- Contenido completo de `~/start-vnc.sh` y `~/.config/systemd/user/wayvnc-lan.service`.
- Configuración de autenticación/cifrado actual de `WayVNC` (`~/.config/wayvnc/config`) y `smb.conf` (versión mínima de protocolo SMB).
- Reglas activas de firewall (`nftables` / `iptables` / `ufw`).
- Estado real de `loginctl show-user "$USER" -p Linger`.
- Reserva DHCP efectiva en el router doméstico para `192.168.1.52`.
- Propósito y autorización del perfil Wi-Fi secundario `2.4 GHz`.
- SSID y capacidad de comunicación cliente-a-cliente (*AP isolation*) del hotspot del Samsung Galaxy A10 (`MOBILE`).
- Funcionamiento real de `dnsmasq` invocado por `NetworkManager` con `ipv4.method shared` y acceso real desde la Tablet X-View en `10.42.0.1`.

---

## 16. Última auditoría

- **Fecha:** `2026-11-24`.
- **Archivo:** [docs/audits/2026-11-24-system-audit.md](audits/2026-11-24-system-audit.md).
- **Alcance:** inspección de sistema operativo, NetworkManager, interfaces, capacidades Wi-Fi y servicios activos sobre la Raspberry Pi real (transcripción estructurada en el repositorio).

---

## 17. Referencias a documentación relacionada

- [README.md](../README.md) — visión general del proyecto.
- [AGENTS.md](../AGENTS.md) — reglas de trabajo para agentes y colaboradores.
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — arquitectura general de hardware y software.
- [docs/NETWORKING.md](NETWORKING.md) — diseño y operación de los modos de red.
- [docs/INSTALLATION.md](INSTALLATION.md) — despliegue controlado y mecanismo de recuperación.
- [docs/SECURITY.md](SECURITY.md) — controles de seguridad y consideraciones con Windows 8.1.
- [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) — diagnóstico de fallos frecuentes.
- [tests/network-test-plan.md](../tests/network-test-plan.md) — plan de pruebas T01–T19.
