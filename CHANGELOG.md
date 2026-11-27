# Changelog

El formato de este archivo está inspirado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y sigue la convención de [Semantic Versioning](https://semver.org/lang/es/).

> **Nota sobre trazabilidad:** los hitos `v0.1.0` a `v0.3.0` han sido reconstruidos retrospectivamente a partir de la bitácora histórica del proyecto y de la auditoría técnica del 24 de noviembre de 2026, sin inventar fechas de publicación ni etiquetas Git inexistentes. `v0.4.0` se publica como versión funcional validada en sus características principales; no se crean tags ni releases adicionales.

---

## [0.4.0] — NOMAD UPDATE (2026-11-27)

### Added

- Instalador idempotente `install.sh` con comprobación previa, conservación de la configuración local e instalación de archivos de sistema sin activar NOMAD ni habilitar el fallback.
- Reestructuración integral del repositorio bajo la jerarquía `docs/`, `software/`, `tests/`, `hardware/`, `firmware/` y `assets/`.
- Memoria técnica permanente en `docs/TECHNICAL_CONTEXT.md` con clasificación explícita de estados (`CONFIRMED`, `REPORTED`, `IMPLEMENTED`, `PLANNED`, `UNKNOWN`).
- Registros de auditoría: `docs/audits/2026-11-24-system-audit.md` y `docs/audits/2026-11-26-nomad-deployment.md`, este último con el despliegue físico informado por el propietario.
- Instrucciones permanentes para agentes de IA y colaboradores en `AGENTS.md`.
- Hoja de ruta evolutiva en `ROADMAP.md` y propuesta de licencia MIT en `LICENSE`.
- Decisión de arquitectura `docs/decisions/ADR-001-network-modes.md` que define los modos `HOME`, `MOBILE` y `NOMAD`.
- Documentación técnica de arquitectura, redes, instalación/recuperación, seguridad y resolución de problemas en `docs/`.
- Script de gestión de red `software/scripts/dorsett-network.sh` con soporte para `status`, `fallback`, `home`, `mobile`, `nomad`, `confirm`, `rollback`, `--dry-run`, bloqueo concurrente y protección para sesiones remotas.
- Script de aprovisionamiento `software/scripts/setup-hotspot.sh` para crear o actualizar el perfil `Dorsett-AP` sin activarlo automáticamente.
- Sistema de diagnóstico read-only y sanitizado `software/scripts/collect-diagnostics.sh`.
- Unidad de servicio `software/systemd/dorsett-fallback.service` para selección de respaldo al arranque.
- Plantilla de configuración externalizada `software/config/network.env.example` y exclusiones de seguridad en `.gitignore`.
- Plan de pruebas `tests/network-test-plan.md` (escenarios T01–T19) y suite automatizada `tests/test-network.sh` basada en *mocks* de `nmcli`.

### Changed

- Reescritura y saneamiento de `README.md`: eliminación de texto conversacional residual, corrección de bloques Markdown, separación entre autonomía de red y energética, y sanitización de identificadores personales.
- Procedimiento de despliegue con comprobación previa del temporizador, confirmación desde la Tablet y prueba de arranque aislado.
- Documentación actualizada para reflejar `HOME` y `NOMAD` operativos, incluido el arranque autónomo; `MOBILE` continúa pendiente de configuración y validación.
- `setup-hotspot.sh` aplica y valida `802-11-wireless-security.wps-method 1` en perfiles nuevos y existentes, con reflejo en `--dry-run` y en la suite simulada. WPA2, RSN y CCMP se mantienen sin cambios.

### Fixed

- Una configuración con `MOBILE_PROFILE=""` permite el fallback a NOMAD mientras se registra el hotspot del teléfono.
- El aprovisionamiento WPA2 evita que el editor de `nmcli` guarde la PSK en su historial y verifica el valor persistido sin imprimirlo.
- `install.sh` usa `PAGER=cat LC_ALL=C timeout 10s nmcli -f NAME,TYPE,DEVICE connection show`. La causa exacta del fallo original con columnas de autoconexión no quedó determinada; no se atribuye exclusivamente al paginador.

### Validated

- Pruebas físicas ejecutadas por el propietario en Raspberry Pi 5 los días 26 y 27 de noviembre de 2026: instalación corregida, DHCP, SSH, Samba, TightVNC, temporizador de 300 segundos, arranque sin router, transferencia real de archivos y persistencia de NOMAD al reaparecer la red doméstica.
- Suite simulada local: `bash -n` correcto y `56 PASS / 0 FAIL / 2 SKIP`; `shellcheck` y `systemd-analyze` no disponibles en la estación.
- No se declaran aprobados todos los escenarios `T01`–`T19`; quedan pendientes `MOBILE`, el regreso manual tras arranque aislado, la recuperación dinámica y la interfaz gráfica.

---

## [0.3.0] — Network Stability (Hito histórico reconstruido)

### Changed

- Auditoría de perfiles Wi-Fi en `NetworkManager` para mitigar asociaciones erráticas a redes secundarias al arrancar.
- Configuración y confirmación de prioridad de autoconexión `100` en el perfil doméstico autorizado.

### Fixed

- Recuperación de visibilidad en subred local (`192.168.1.52/24`) para restablecer el acceso SSH (`22`) y TightVNC (`5901`).

### Audit

- Auditoría técnica ejecutada sobre la Raspberry Pi 5 real el 24 de noviembre de 2026 (confirmando Debian 13.6 ARM64, NetworkManager 1.52.1, capacidades `iw list` y servicios activos).

---

## [0.2.0] — Local Network Ecosystem (Hito histórico reconstruido)

### Added

- Implementación del servicio Samba (`smbd`, TCP `445`) como NAS local con directorio compartido (`~/compartido`).
- Integración de flujos de compartición e intercambio de archivos entre Raspberry Pi 5, Tablet Windows 8.1, PC de escritorio y smartphone Android dentro de la LAN local.

---

## [0.1.0] — Remote Access Foundation (Hito histórico reconstruido)

### Added

- Configuración inicial de Linux ARM64 en Raspberry Pi 5 (`raspi-ali`).
- Habilitación de administración remota por `ssh` (TCP `22`).
- Despliegue de segunda instancia de `WayVNC` en TCP `5901` (`0.0.0.0:5901`) compatible con TightVNC Viewer en Windows 8.1 de 32 bits, preservando la instancia secundaria en TCP `5900`.
- Creación de `~/start-vnc.sh` y unidad de usuario `~/.config/systemd/user/wayvnc-lan.service` con persistencia reportada vía `loginctl enable-linger`.
