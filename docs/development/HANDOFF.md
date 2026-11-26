# HANDOFF — Recuperación y finalización de v0.4.0

Registro vivo de la intervención de mantenimiento. Los estados se clasifican según `AGENTS.md`: `IMPLEMENTED`, desplegado, `CONFIRMED` (hardware), `REPORTED`, `UNKNOWN`.

---

## Fase 1 — Estado inicial (2026-11-24)

- **Rama actual:** `main` (`git status -sb`: `## No commits yet on main...origin/main [gone]`).
- **Estado de Git:** repositorio sin commits; todo el árbol de trabajo aparece como `??` (sin staging).
- **Entorno de ejecución:** estación de desarrollo Windows (según `AGENTS.md` y `docs/TECHNICAL_CONTEXT.md`); no se accede a la Raspberry Pi real.
- **Archivos verificados como existentes:**
  - `software/scripts/dorsett-network.sh`
  - `software/scripts/setup-hotspot.sh`
  - `software/scripts/collect-diagnostics.sh`
  - `software/systemd/dorsett-fallback.service`
  - `tests/test-network.sh`
- **Documentación previa leída:** `AGENTS.md`, `README.md`, `docs/TECHNICAL_CONTEXT.md`, `ROADMAP.md`, `CHANGELOG.md`, `docs/decisions/ADR-001-network-modes.md`, `docs/audits/2026-11-24-system-audit.md` (parcial) y `.gitignore`.
- **Alcance de versión:** `v0.4.0 Nomad Update` permanece en `[Unreleased]`; modos `HOME`/`MOBILE`/`NOMAD` implementados en código, sin validación física.
- **Incidente reportado por el contexto heredado (NO reproducido en esta sesión):** fallo en `tests/test-network.sh` localizado inicialmente en `T04` con código de salida `7`. `T04` comprueba la activación de `Dorsett-AP` cuando `HOME` y `MOBILE` no están disponibles. Antigravity habría modificado posteriormente scripts y mocks sin validarlos.
- **Estado del fallo en este momento:** `REPORTED` / `UNKNOWN`. No se afirma que `T04` siga fallando hasta reproducirlo.

### Acciones de la Fase 1

- Ejecutado `git status --short` y `git status -sb`.
- Creado `docs/development/` y este archivo `HANDOFF.md`.
- No se han modificado scripts, servicios ni pruebas.

---

## Fase 2 — Validación inicial (2026-11-24)

- **Entorno Bash detectado:** `C:\laragon\bin\git\bin\bash.exe`, GNU bash `5.2.37(1)-release`, `MINGW64_NT-10.0-26300`, `x86_64-pc-msys` (Windows/MSYS2). `command -v nmcli` no devolvió ninguna ruta: no hay NetworkManager real accesible desde esta estación.
- **Inspección previa de `tests/test-network.sh`:** suite con `set -euo pipefail`; valida sintaxis, LF, unidad systemd y enlaces Markdown, y ejecuta escenarios T01–T19 mediante mocks locales de `nmcli`, `ip`, `systemd-run`, `systemctl`, `dnsmasq`, `iw`, `ss`, `journalctl` y `loginctl` (`tests/test-network.sh:166-448`). El escenario T04 está en `tests/test-network.sh:506-513` y comprueba activación de `Dorsett-AP` y dirección `10.42.0.1/24` (`CONFIRMED` solo como resultado simulado).
- **Aislamiento de red verificado:** los scripts resuelven cada herramienta mediante variables `DORSETT_*_BIN` (`dorsett-network.sh:49-52`, `setup-hotspot.sh:34-35`, `collect-diagnostics.sh:19-25`) y la suite las apunta a los mocks (`tests/test-network.sh:436-447`). No se realizaron conexiones SSH, cambios de red ni operaciones `sudo`.
- **Comandos y resultados reales observados:**
  - `bash -n` sobre los tres scripts y la suite: código `0` en los cuatro casos.
  - `bash tests/test-network.sh` (1.ª ejecución): `PASS: 43 | FAIL: 0 | SKIP: 2`, código de salida `0`.
  - `bash tests/test-network.sh` (2.ª ejecución de estabilidad): `PASS: 43 | FAIL: 0 | SKIP: 2`, código de salida `0`.
  - T04 pasó en ambas ejecuciones: `[PASS] T04 fallback activa Dorsett-AP cuando no hay conexión` y `[PASS] T04 modo NOMAD obtiene 10.42.0.1/24`.
  - `SKIP`: `shellcheck` y `systemd-analyze` no disponibles. No se instalaron dependencias.
- **Primer fallo reproducible:** ninguno. El fallo histórico de T04 con exit `7` queda registrado como `REPORTED`, no confirmado en esta sesión; las modificaciones previas de Antigravity quedan validadas solo en el plano simulado.
- **Estado:** suite simulada aprobada en MSYS/Windows; no equivale a validación física en Raspberry Pi 5 (`CONFIRMED` en hardware sigue pendiente).

---

## Fase 3 — Corrección (2026-11-24)

- **No aplicable:** no existió fallo reproducible en Fase 2. No se aplicaron correcciones a scripts, mocks ni expectativas; se conserva el trabajo previo sin cambios no justificados.
- Se respetó el límite de dos intentos de corrección (no consumidos).
- Si apareciera un fallo en hardware real, el siguiente paso sería reproducirlo con el plan `tests/network-test-plan.md` sobre la Raspberry Pi, sin alterar pruebas válidas.

---

## Fase 4 — Preparación para publicar (2026-11-24)

Verificaciones realizadas:

- `README.md`: refleja `v0.4.0` como **implementado en repositorio / sin validar en Pi**, distingue autonomía de red y energética y enumera capacidades confirmadas, reportadas y planificadas. Sin cambios necesarios.
- `CHANGELOG.md`: mantiene `## [Unreleased] — v0.4.0 Nomad Update`; no se crearon tags ni versiones oficiales.
- `docs/TECHNICAL_CONTEXT.md`: conserva la convención `CONFIRMED` / `REPORTED` / `IMPLEMENTED` / `PLANNED` / `UNKNOWN` y separa datos de auditoría de hipótesis pendientes. Sin cambios necesarios.
- `docs/development/HANDOFF.md`: actualizado con las cuatro fases y el último estado de desarrollo.
- **Secretos:** ningún archivo `.env`, `.nmconnection`, `*.key`, `*.pem`, `*.psk`, `*.secret` ni clave privada presente en el árbol. Único archivo de configuración: `software/config/network.env.example` con valores de ejemplo (`home-profile`, `mobile-profile`) y sin PSK. Los MAC/UUID en `tests/test-network.sh:648-649` son valores ficticios de mock para comprobar sanitizado.
- `.gitignore`: excluye `.env*`, `*.env` (excepto ejemplos), claves, `*.nmconnection`, `diagnostics/`, `*diagnostics-*.md`, `docs/audits/local/` y logs/temporales.
- **Enlaces relativos del README:** validados por la suite (`[PASS] Todos los enlaces relativos Markdown (30) existen`, código `0` en tres ejecuciones).
- **Estado NOMAD:** `IMPLEMENTED` en repositorio; **no** declarado operativo. Las pruebas físicas T01–T19 en Raspberry Pi siguen pendientes.
- **Git:** sin commits en `main` (`No commits yet on main...origin/main [gone]`); único cambio nuevo de esta intervención es `docs/development/HANDOFF.md`. No se ejecutó `git push`, `git add`, `git commit` ni creación de tags.

### Último estado

Suite simulada aprobada (43 PASS / 0 FAIL / 2 SKIP; shellcheck y systemd-analyze omitidos por ausencia en Windows). Sin bloqueadores para publicar el repositorio tal como está; bloqueador para declarar NOMAD operativo: ausencia de pruebas físicas.

## Fase 5 — Preparación del despliegue NOMAD (2026-11-26)

- **Git:** rama `main`, con historial y árbol limpio al inicio. Cambios locales sin publicar. `v0.4.0` sigue en `[Unreleased]`.
- **`IMPLEMENTED`:** `install.sh` comprueba requisitos locales, instala scripts y unidad como `root:root`, conserva la configuración con permisos `0600` y recarga las unidades. La habilitación queda a cargo del propietario después de la prueba manual.
- **Correcciones:** `MOBILE_PROFILE=""` permite planificar el despliegue sin el teléfono. El editor de `nmcli` recibe la PSK por entrada estándar con el historial bloqueado y el script compara la PSK persistida sin mostrarla.
- **Selección al arrancar:** un cliente desconocido conectado con IPv4 utilizable se conserva y deja una advertencia. Si carece de IPv4 utilizable, el AP puede reemplazarlo tras la espera. Se conserva NOMAD operativo y el servicio no realiza búsquedas periódicas de HOME.
- **Validación estática local:** `bash -n` aprobó el instalador, los tres scripts de red y la suite en Bash/MSYS. `--help` funcionó y `--check` rechazó Windows por plataforma.
- **Validación simulada:** `bash tests/test-network.sh` devolvió **47 PASS / 0 FAIL / 2 SKIP**. T04 activó el AP con MOBILE vacío y obtuvo `10.42.0.1/24`. La prueba de aprovisionamiento comprobó el guardado simulado sin exponer la PSK ni activar el AP. `shellcheck` y `systemd-analyze` se omitieron por ausencia.
- **Pendiente en Raspberry Pi:** comprobar instalación e idempotencia en Debian ARM64, comprobar el temporizador y el regreso a HOME, validar WPA2, DHCP, SSH, TightVNC y Samba, y verificar el arranque aislado. Para la prueba de arranque hace falta un acceso de rescate que funcione con el router apagado. [Guía de despliegue](../INSTALLATION.md)
