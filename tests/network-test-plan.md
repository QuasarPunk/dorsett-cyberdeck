# Plan de Pruebas de Red y Recuperación — Dorsett v0.4.0

Este documento define los **19 escenarios de verificación (`T01`–`T19`)** para validar la arquitectura de modos `HOME`, `MOBILE` y `NOMAD`, el servicio `dorsett-fallback.service`, la recuperación remota y el sistema de diagnóstico.

> **Regla de veracidad:** las pruebas automatizadas mediante `tests/test-network.sh` utilizan *mocks* de `nmcli`, `ip`, `systemd-run`, `systemctl`, `iw`, `ss`, `journalctl` y `loginctl`. **Nunca sustituyen a las pruebas físicas sobre la Raspberry Pi 5 real.** Ningún escenario físico puede declararse aprobado sin evidencia directa en hardware.

---

## Matriz de escenarios (`T01`–`T19`)

| ID | Escenario | Condición / Entrada | Resultado esperado | Cobertura automatizada (Mock) | Prueba física (Raspberry Pi 5) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T01** | `HOME` disponible al arrancar | `wlan0` conectado a `HOME_PROFILE` con IPv4 válida (`192.168.1.52/24`) | `HOME` permanece activo sin interrupciones | `tests/test-network.sh` | Pendiente |
| **T02** | `HOME` disponible sin Internet | Router doméstico sin salida WAN (`192.168.1.52/24`) | `HOME` permanece activo; no hay *fallback* ni *ping* externo | `tests/test-network.sh` | Pendiente |
| **T03** | `HOME` ausente y `MOBILE` disponible | `wlan0` conectado a `MOBILE_PROFILE` con IPv4 válida del smartphone | `MOBILE` permanece activo | `tests/test-network.sh` | Pendiente |
| **T04** | `HOME` y `MOBILE` ausentes | `wlan0` desconectado tras ventana inicial (`FALLBACK_TIMEOUT`) | Se activa `Dorsett-AP` (`10.42.0.1/24`, modo `NOMAD`) | `tests/test-network.sh` | Pendiente |
| **T05** | `NOMAD` y conexión de Tablet | Tablet X-View (Win 8.1) se asocia al SSID `Dorsett-AP` | Asignación DHCP válida en `10.42.0.x` vía `dnsmasq` | No aplicable (requiere radio física + Tablet) | Pendiente |
| **T06** | `NOMAD` y acceso SSH | Cliente conectado a `Dorsett-AP` abre SSH hacia `10.42.0.1:22` | Autenticación correcta y consola operativa | No aplicable (requiere hardware) | Pendiente |
| **T07** | `NOMAD` y acceso TightVNC | TightVNC Viewer en Tablet Win 8.1 apunta a `10.42.0.1::5901` | Escritorio Wayland/labwc visible y control táctil funcional | No aplicable (requiere hardware) | Pendiente |
| **T08** | `NOMAD` y acceso Samba | Cliente accede a `\\10.42.0.1` | Lectura y escritura autorizadas sobre `~/compartido` | No aplicable (requiere hardware) | Pendiente |
| **T09** | Resolución mDNS | Cliente resuelve `raspi-ali.local` en `HOME` y `NOMAD` | Resuelve cuando el cliente/red lo soporta; si falla, IP directa es operativa | No aplicable (requiere red real) | Pendiente |
| **T10** | Reaparición de `HOME` con `NOMAD` activo | `Dorsett-AP` activo mientras vuelve señal del router doméstico | `dorsett-network fallback` / servicio no interrumpe `NOMAD` | `tests/test-network.sh` | Pendiente |
| **T11** | Regreso manual a `HOME` | Operador ejecuta `dorsett-network home` | Transición controlada a `HOME_PROFILE` y recuperación de servicios | `tests/test-network.sh` (simulado) | Pendiente |
| **T12** | Fallo durante una transición remota | Transición manual desde sesión SSH sin `dorsett-network confirm` | Temporizador independiente (`systemd-run`) ejecuta `rollback` y restaura perfil previo | `tests/test-network.sh` (mock `systemd-run` + ejecución `rollback`) | Pendiente |
| **T13** | Reinicio de la Raspberry Pi | Reboot completo con `dorsett-fallback.service` habilitado | Persistencia de perfiles y selección automática correcta al arranque | No aplicable (requiere reboot físico) | Pendiente |
| **T14** | Perfil AP inexistente | Se ejecuta `fallback` o `nomad` sin existir `Dorsett-AP` | Error informativo (`exit 5`), sin cambios destructivos | `tests/test-network.sh` | Pendiente |
| **T15** | Perfil Wi-Fi desconocido activo | `wlan0` conectado a perfil no listado como `HOME`/`MOBILE`/`AP` | Aviso en logs y preservación de conexión sin adoptarlo | `tests/test-network.sh` | Pendiente |
| **T16** | DHCP lento | `wlan0` permanece en estado `activating` (ej. `70`) más allá de `FALLBACK_TIMEOUT` | Espera acotada sin bucle infinito; transición controlada a `NOMAD` | `tests/test-network.sh` | Pendiente |
| **T17** | Ejecuciones simultáneas | Dos invocaciones paralelas de `dorsett-network` | El bloqueo (`flock` / respaldo atómico) impide colisiones (`exit 4`) | `tests/test-network.sh` | Pendiente |
| **T18** | Fallo de NetworkManager o interfaz ausente | `NetworkManager` detenido o `wlan0` inexistente | Diagnóstico claro y salida controlada (`exit 3`) | `tests/test-network.sh` | Pendiente |
| **T19** | Captura de diagnósticos | Ejecución de `collect-diagnostics.sh` | Informe Markdown completo, sin secretos, sin `--show-secrets` y MAC/UUID/SSID sanitizados | `tests/test-network.sh` | Pendiente |

---

## Criterio de aprobación para despliegue

1. `tests/test-network.sh` debe pasar al 100% en entorno de desarrollo (validación estática + *mocks*).
2. Durante la fase de despliegue controlado en la Raspberry Pi 5 real, se deben ejecutar y registrar en una nueva auditoría fechada en `docs/audits/` los resultados reales de `T01`–`T19`.
3. `dorsett-fallback.service` solo se habilitará (`systemctl enable`) después de superar `T05`–`T08`, `T11` y `T12` en hardware real.
