# Plan de Pruebas de Red y Recuperación — Dorsett v0.4.0

Este documento define los **19 escenarios de verificación (`T01`–`T19`)** para validar la arquitectura de modos `HOME`, `MOBILE` y `NOMAD`, el servicio `dorsett-fallback.service`, la recuperación remota y el sistema de diagnóstico.

> **Regla de veracidad:** las pruebas automatizadas mediante `tests/test-network.sh` utilizan *mocks* de `nmcli`, `ip`, `systemd-run`, `systemctl`, `iw`, `ss`, `journalctl` y `loginctl`. **Nunca sustituyen a las pruebas físicas sobre la Raspberry Pi 5 real.** Las pruebas físicas de los días 26 y 27 de noviembre de 2026 fueron ejecutadas por el **propietario**, no por el agente de IA, y se registran en [docs/audits/2026-11-26-nomad-deployment.md](../docs/audits/2026-11-26-nomad-deployment.md).

---

## Matriz de escenarios (`T01`–`T19`)

| ID | Escenario | Cobertura automatizada (Mock) | Estado físico documentado |
| :--- | :--- | :--- | :--- |
| **T01** | `HOME` disponible al arrancar | `tests/test-network.sh` | **Parcial:** HOME reconocido y operativo; el arranque con HOME no fue descrito explícitamente en la auditoría de despliegue |
| **T02** | `HOME` disponible sin Internet | `tests/test-network.sh` | **Pendiente** de escenario físico específico |
| **T03** | `HOME` ausente y `MOBILE` disponible | `tests/test-network.sh` | **Pendiente:** `MOBILE_PROFILE=""`; el Galaxy A10 fue cliente de NOMAD, no perfil móvil de Dorsett |
| **T04** | `HOME` y `MOBILE` ausentes → `Dorsett-AP` | `tests/test-network.sh` | **Confirmado:** arranque real sin router con redes secundarias gestionadas por el propietario; AP activado automáticamente |
| **T05** | `NOMAD` y concesión DHCP | No aplicable (radio + clientes reales) | **Confirmado:** rango `10.42.0.10`–`10.42.0.254`; Galaxy A10 y Windows recibieron IP; advertencia `CAP_CHOWN` no bloqueante |
| **T06** | `NOMAD` y acceso SSH | No aplicable (requiere hardware) | **Confirmado:** autenticación SSH sobre `10.42.0.1` |
| **T07** | `NOMAD` y acceso TightVNC | No aplicable (requiere hardware) | **Confirmado:** acceso desde la Tablet cuando se conectó a `Dorsett-AP`; el fallo inicial se debió a que estaba en el router doméstico |
| **T08** | `NOMAD` y acceso Samba | No aplicable (requiere hardware) | **Confirmado:** TCP `445` accesible y acceso con credenciales del usuario Samba; transferencia real de archivos sin router |
| **T09** | Resolución mDNS | No aplicable (requiere red real) | **Pendiente:** la IP `10.42.0.1` es el método de referencia |
| **T10** | Reaparición de HOME con NOMAD activo | `tests/test-network.sh` | **Confirmado:** NOMAD persistió al reaparecer la red doméstica; retorno automático intencionalmente ausente |
| **T11** | Regreso manual a HOME | `tests/test-network.sh` (simulado) | **Confirmado en pruebas anteriores**; queda pendiente una confirmación específica del regreso manual desde NOMAD después del arranque aislado |
| **T12** | Fallo durante transición remota y rollback | `tests/test-network.sh` (mock `systemd-run` + `rollback`) | **Parcial:** recuperación temporizada de 300 s comprobada físicamente en la prueba NOMAD; no se documentó un fallo de transición exacto |
| **T13** | Reinicio de la Raspberry Pi con fallback | No aplicable (requiere reboot físico) | **Confirmado:** arranque real sin router, `dorsett-fallback.service` habilitado y AP activado |
| **T14** | Perfil AP inexistente | `tests/test-network.sh` | **Pendiente** en hardware; validado solo con mocks |
| **T15** | Perfil Wi-Fi desconocido activo | `tests/test-network.sh` | **Pendiente** como escenario controlado; las redes secundarias fueron gestionadas por el propietario antes de la prueba aislada |
| **T16** | DHCP lento / link-local | `tests/test-network.sh` | **Pendiente** en hardware |
| **T17** | Ejecuciones simultáneas | `tests/test-network.sh` | **Pendiente** en hardware |
| **T18** | NetworkManager detenido o interfaz ausente | `tests/test-network.sh` | **Pendiente** en hardware |
| **T19** | Captura de diagnósticos sanitizados | `tests/test-network.sh` | **Pendiente** en hardware; saneamiento verificado con mocks |

---

## Verificación adicional del empaquetado

- `install.sh`: corrección de la consulta de perfiles incorporada y comprobada estáticamente (`PAGER=cat LC_ALL=C`, columnas `NAME,TYPE,DEVICE`); la causa del fallo original no quedó determinada.
- `setup-hotspot.sh`: `wps-method 1` aplicado a perfiles nuevos y existentes, reflejado en `--dry-run` y verificado en la validación final; WPA2/RSN/CCMP se mantienen.
- Resultado local de la suite: **56 PASS / 0 FAIL / 2 SKIP**. `shellcheck` y `systemd-analyze` no estaban disponibles.

---

## Criterio de cierre de `v0.4.0`

1. La suite simulada pasa sin fallos; la cobertura con mocks no se presenta como evidencia de hardware.
2. La auditoría [2026-11-26-nomad-deployment.md](../docs/audits/2026-11-26-nomad-deployment.md) registra los resultados físicos informados por el propietario.
3. `HOME` y `NOMAD` se declaran operativos; `NOMAD` incluye arranque autónomo. `MOBILE` queda pendiente de configuración y validación.
4. **No se declaran aprobados todos los escenarios `T01`–`T19`.** Quedan pendientes el regreso manual tras arranque aislado, la recuperación dinámica durante la ejecución y la interfaz gráfica.
