# Memoria Técnica Permanente — Proyecto Dorsett

Este documento constituye la memoria técnica viva del **Proyecto Dorsett** (`dorsett-cyberdeck`, ecosistema **QuasarPunk**). Su objetivo es permitir que cualquier desarrollador o agente de IA comprenda el estado real, la arquitectura y las incógnitas del sistema sin depender de conversaciones previas.

> **Política de sanitización pública:** esta memoria técnica no almacena contraseñas, claves PSK, claves privadas SSH, direcciones MAC personales, UUID reales de perfiles ni nombres personales de redes domésticas o secundarias. Dichos valores locales deben residir únicamente en el sistema objetivo (`/etc/dorsett/network.env` o perfiles protegidos de `NetworkManager`), excluidos de Git.

> **Origen de las pruebas físicas (`2026-11-26`/`2026-11-27`):** ejecutadas por el propietario sobre la Raspberry Pi 5. El agente de IA solo transcribió los resultados y ejecutó validaciones estáticas y simuladas en la estación de desarrollo.

---

## Convención de estados

Cada dato técnico significativo se etiqueta explícitamente con uno de los siguientes estados:

- **`CONFIRMED`**: verificado en hardware por el propietario, en la auditoría del `2026-11-24` o en las pruebas físicas del `2026-11-26`/`2026-11-27` documentadas en `docs/audits/`.
- **`DEPLOYED`**: instalado en la Raspberry Pi real e informado por el propietario.
- **`REPORTED`**: informado por el propietario o por documentación previa del repositorio sin verificación directa por comandos recientes.
- **`IMPLEMENTED`**: desarrollado en el repositorio; no implica por sí solo despliegue o validación física.
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
- **Capa de conectividad autónoma `v0.4.0` (en repositorio y desplegada):**
  - `software/scripts/dorsett-network.sh` — CLI para consultar estado, ejecutar *fallback* al arranque y realizar conmutaciones controladas [`IMPLEMENTED` / `DEPLOYED`; conmutación con reversión de 300 s `CONFIRMED`, `2026-11-26`].
  - `software/scripts/setup-hotspot.sh` — aprovisionamiento seguro del perfil `Dorsett-AP`, con WPS deshabilitado (`wps-method 1`) para perfiles nuevos y existentes, sin activarlo automáticamente [`IMPLEMENTED` / `DEPLOYED`, `2026-11-26`].
  - `software/scripts/collect-diagnostics.sh` — recolección sanitizada de estado en solo lectura [`IMPLEMENTED`; validación simulada].
  - `software/systemd/dorsett-fallback.service` — unidad *oneshot* de sistema tras `NetworkManager.service`, habilitada y probada en arranque sin router [`DEPLOYED` / `CONFIRMED`, `2026-11-26`].
  - `software/config/network.env.example` — plantilla de variables externas [`IMPLEMENTED` / `DEPLOYED`].

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
| `HOME` | Configurado en `HOME_PROFILE` (`/etc/dorsett/network.env`) | Cliente Wi-Fi doméstico | Sí / `100` | `CONFIRMED` en host e integrado en la configuración local (`2026-11-26`) |
| `MOBILE` | Configurado en `MOBILE_PROFILE` (hotspot Galaxy A10) | Cliente Wi-Fi móvil | Sí / `50` | `PLANNED` / `UNKNOWN` (perfil vacío durante la prueba; Galaxy A10 actuó como cliente NOMAD) |
| `NOMAD` | `Dorsett-AP` (SSID `Dorsett-AP`) | Access Point (`10.42.0.1/24`, `shared`) | No / N/A | `DEPLOYED` / `CONFIRMED`; creado, WPS deshabilitado y activado automáticamente sin router (`2026-11-26`) |

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
| `dorsett-fallback.service` | N/A (`oneshot`) | Instalado y habilitado; activó `Dorsett-AP` en arranque sin router | Único disparo al arranque; sin retorno automático a HOME | `DEPLOYED` / `CONFIRMED` (`2026-11-26`) |

---

## 9. Rutas de archivos relevantes

### En la Raspberry Pi (sistema objetivo)

- `~/.config/systemd/user/wayvnc-lan.service` — unidad systemd de usuario para WayVNC LAN [`CONFIRMED`, `2026-11-24`].
- `~/start-vnc.sh` — script de arranque de WayVNC LAN (contenido exacto no inspeccionado) [`CONFIRMED` existencia / `UNKNOWN` contenido].
- `~/compartido` (reportado como `/home/ali/compartido`) — carpeta compartida por Samba [`REPORTED`].
- `/usr/sbin/dnsmasq` — binario de `dnsmasq` instalado [`CONFIRMED`, `2026-11-24`].
- `/etc/os-release` — identificación del sistema base [`CONFIRMED`, `2026-11-24`].

### Rutas de despliegue (`v0.4.0`) — `DEPLOYED` / `CONFIRMED`

`bash install.sh --check` comprueba los requisitos de la Pi. `sudo bash install.sh` instala las copias de sistema y conserva el contenido de `network.env` en actualizaciones. El propietario registró HOME con el nombre exacto y dejó `MOBILE_PROFILE=""`. El aprovisionamiento de NOMAD guarda la PSK en NetworkManager con el historial del editor bloqueado. Tras la prueba manual se habilitó el fallback. La consulta de perfiles del instalador se corrigió a `PAGER=cat LC_ALL=C timeout 10s nmcli -f NAME,TYPE,DEVICE connection show`; la causa exacta del fallo previo no quedó determinada. [Procedimiento de despliegue](INSTALLATION.md)

- `/usr/local/bin/dorsett-network`
- `/usr/local/sbin/dorsett-setup-hotspot`
- `/usr/local/bin/dorsett-collect-diagnostics` *(opcional recomendado)*
- `/etc/dorsett/network.env` (`root:root`, `0600`)
- `/etc/systemd/system/dorsett-fallback.service`

---

## 10. Dependencias instaladas

- `NetworkManager` (`1.52.1`) [`CONFIRMED`].
- `dnsmasq` (`/usr/sbin/dnsmasq`) [`CONFIRMED`; iniciado bajo `ipv4.method shared`, rango DHCP observado `10.42.0.10`–`10.42.0.254` y concesión al Galaxy A10 (`2026-11-26`)].
- `openssh-server` (`ssh`), `samba` (`smbd`), `avahi-daemon`, `wayvnc`, `iw`, `iproute2` (`ip`, `ss`) [`CONFIRMED`].
- `shellcheck` / herramientas adicionales de validación: no verificadas en la Raspberry Pi [`UNKNOWN`].

---

## 11. Configuraciones conocidas

- Perfil doméstico con DHCP en `wlan0`, IP observada `192.168.1.52/24`, gateway `192.168.1.1`, métrica `600`, prioridad `100` [`CONFIRMED`].
- Reserva DHCP estática en el router para `192.168.1.52`: reportada por el usuario como IP estable, pero reserva en router no comprobada directamente [`REPORTED` / `UNKNOWN`].
- Persistencia de sesión de usuario mediante `loginctl enable-linger` para `wayvnc-lan.service`: informada en `README.md` previo, pendiente de verificación directa [`REPORTED` / `UNKNOWN`].
- Dirección del modo `NOMAD`: `10.42.0.1/24` con `ipv4.method shared`, canal `6` (`2.4 GHz`, banda `bg`), WPA2-PSK/RSN/CCMP, `autoconnect=no`, IPv6 deshabilitado y `802-11-wireless-security.wps-method 1` [`DEPLOYED` / `CONFIRMED` en `2026-11-26`].
- Resultados físicos de NOMAD: Windows con IPv4 `10.42.0.212`, cuatro `ping` a `10.42.0.1` recibidos (`0 %` de pérdida, promedio `5 ms`), SSH, TCP `5901`/`445`, Samba con credenciales del usuario Samba y TightVNC desde la Tablet conectada al AP [`CONFIRMED` por el propietario].
- Advertencia `CAP_CHOWN` de `dnsmasq` observada sin impedir la concesión DHCP [`CONFIRMED`].

---

## 12. Particularidades del entorno gráfico

- El entorno gráfico se ejecuta sobre **Wayland / `labwc`** [`REPORTED`].
- Existen **dos instancias de `WayVNC`**: una en TCP `5900` y otra dedicada en TCP `5901` (`-r 0.0.0.0 5901`) para compatibilidad con TightVNC Viewer en la Tablet X-View con Windows 8.1 de 32 bits [`CONFIRMED` puertos/proceso / `REPORTED` motivo de compatibilidad].
- Se observó la advertencia en WayVNC:
  `Warning: ../src/output.c:300: Output NOOP-1 power state failure.` [`CONFIRMED`].
- Los problemas iniciales de VNC se debieron a que la Tablet permanecía conectada al router doméstico y no a `Dorsett-AP`; al conectarla al AP, TightVNC funcionó [`CONFIRMED` por el propietario].
- La Tablet Windows 8.1 y TightVNC son actualmente una solución de visualización provisional; la pantalla HDMI directa es un objetivo futuro.

---

## 13. Problemas conocidos

1. **Advertencia `Output NOOP-1 power state failure` en WayVNC:** registrada como incidencia observada (`CONFIRMED`), sin evidencia de fallo crítico en operación; no modificar WayVNC sin diagnóstico previo.
2. **Prefijo `netplan-` en perfiles de NetworkManager:** riesgo de sobrescritura o duplicación si se edita Netplan y NetworkManager simultáneamente sin determinar el origen [`CONFIRMED` prefijo / `UNKNOWN` configuración `/etc/netplan`].
3. **Perfil secundario 2.4 GHz con autoconexión habilitada:** su propósito y autorización no están confirmados (`UNKNOWN`); podría competir si el perfil doméstico no está disponible.
4. **Windows 8.1 de 32 bits en la Tablet X-View:** sistema operativo sin soporte regular de seguridad; requiere precauciones de aislamiento de red y compatibilidad de cifrado/autenticación en VNC y SMB [`REPORTED`].
5. **Ausencia de alimentación portátil:** `v0.4.0` resuelve la autonomía de red (`NOMAD`), no la autonomía energética por baterías [`REPORTED`].
6. **Solicitud de PIN de ocho dígitos en Windows:** observada en la primera prueba, compatible con una solicitud WPS; no se afirma que WPS causara todos los problemas iniciales. Se desactivó con `wps-method 1` [`CONFIRMED` por el propietario; `IMPLEMENTED` en `setup-hotspot.sh`].
7. **Advertencia `CAP_CHOWN` de `dnsmasq`:** observada durante el despliegue, sin impedir DHCP [`CONFIRMED`].
8. **Fallo original del instalador:** la consulta de `nmcli` con columnas de autoconexión falló en la Pi; se sustituyó por un listado con `PAGER=cat LC_ALL=C` y `NAME,TYPE,DEVICE`. Causa exacta [`UNKNOWN`] [`CONFIRMED` la corrección].

---

## 14. Decisiones técnicas vigentes

- **ADR-001 ([docs/decisions/ADR-001-network-modes.md](decisions/ADR-001-network-modes.md)):**
  - `NetworkManager` es el único gestor de conexiones.
  - Arquitectura en tres modos (`HOME`, `MOBILE`, `NOMAD`).
  - Conmutación excluyente cliente/AP en `wlan0` (sin concurrencia STA+AP en `v0.4.0`).
  - Uso de `ipv4.method shared` (`10.42.0.1/24`) aprovechando `dnsmasq` vía NetworkManager.
  - *Fallback* limitado al arranque en `v0.4.0` (sin retorno automático desde `NOMAD` hacia `HOME` para evitar cortar sesiones VNC/SSH activas); comprobado físicamente al reaparecer la red doméstica.
  - `Dorsett-AP` conserva WPA2-PSK/RSN/CCMP y mantiene WPS deshabilitado (`wps-method 1`).
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
- Configuración y validación del perfil `MOBILE` con el hotspot del Galaxy A10 (`MOBILE_PROFILE` quedó vacío y el teléfono fue cliente de NOMAD).
- Regreso manual desde NOMAD a HOME después del arranque aislado (confirmación específica pendiente).
- Resultados físicos de los escenarios no cubiertos por la auditoría de `2026-11-26`, incluidos `T09` (mDNS), `T14`–`T19` y las variantes de recuperación dinámica.
- Causa exacta del fallo original del listado `nmcli` en el instalador.

---

## 16. Última auditoría

- **Fecha:** `2026-11-26`/`2026-11-27`.
- **Archivo:** [docs/audits/2026-11-26-nomad-deployment.md](audits/2026-11-26-nomad-deployment.md).
- **Alcance:** despliegue NOMAD informado por el propietario: instalación, DHCP, SSH, Samba, TightVNC, temporizador, arranque sin router, transferencia de archivos y persistencia de NOMAD. Auditoría anterior: [2026-11-24-system-audit.md](audits/2026-11-24-system-audit.md).

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
- [docs/development/HANDOFF.md](development/HANDOFF.md) — registro de cierre y validaciones de la versión.
