# AGENTS.md — Instrucciones Permanentes para Agentes de IA y Colaboradores

Este archivo define las reglas operativas obligatorias para cualquier agente de IA o colaborador técnico que trabaje en el repositorio `dorsett-cyberdeck` (Proyecto Dorsett, ecosistema QuasarPunk).

---

## 1. Lectura previa obligatoria

Antes de proponer o implementar cambios en el repositorio o en el sistema real:

1. Leer íntegramente [README.md](README.md) y la memoria técnica viva en [docs/TECHNICAL_CONTEXT.md](docs/TECHNICAL_CONTEXT.md).
2. Consultar [ROADMAP.md](ROADMAP.md) y [CHANGELOG.md](CHANGELOG.md) para ubicar el alcance de la versión activa.
3. Revisar los registros de decisiones de arquitectura relevantes en `docs/decisions/` (comenzando por [docs/decisions/ADR-001-network-modes.md](docs/decisions/ADR-001-network-modes.md)).
4. Revisar la última auditoría registrada en `docs/audits/`.
5. Inspeccionar el estado del repositorio con `git status` antes de modificar archivos.

---

## 2. Reglas de entorno y seguridad operacional (Equipo Headless)

La Raspberry Pi 5 (`raspi-ali`) funciona como un equipo **headless** (sin pantalla física dedicada conectada permanentemente). Perder la interfaz de red implica perder el acceso por SSH y WayVNC.

- **No ejecutar cambios disruptivos de red sin autorización explícita** del propietario del sistema.
- **Toda operación que pueda interrumpir la conectividad debe incorporar un mecanismo de recuperación previamente comprobado** (por ejemplo, temporizador de reversión independiente de la sesión SSH o acceso físico alternativo verificado).
- **No desactivar indiscriminadamente** servicios esenciales (`ssh`, `smbd`, `wayvnc-lan.service`, `wayvnc` en `:5900`, `NetworkManager`, `avahi-daemon`).
- **No sustituir componentes operativos sin necesidad** ni alterar la configuración activa de Netplan sin haber auditado su origen y persistencia.
- **No introducir servicios innecesarios** ni dependencias pesadas o propietarias.
- **No confundir entornos:** verificar si las órdenes se ejecutan en la estación de desarrollo (por ejemplo, Windows) o directamente en la Raspberry Pi ARM64.
- **No realizar `git push`** ni publicar cambios remotamente sin autorización explícita.

---

## 3. Reglas de código y compatibilidad

- **Idioma:** documentación principal en **español**; nombres de archivos, scripts, funciones, variables y símbolos de software preferentemente en **inglés**.
- **Compatibilidad objetivo:** Debian GNU/Linux 13 (`trixie`, ARM64) y `NetworkManager` `1.52.1` (utilizando propiedades estables y `LC_ALL=C` al procesar salidas de `nmcli`).
- **Modularidad y claridad:** escribir scripts Bash robustos (`set -euo pipefail`), con funciones pequeñas, validación estricta de argumentos, manejo seguro de nombres con espacios, bloqueo frente a concurrencia (`flock` o equivalente seguro) y sin uso de `eval`.
- **Dependencias mínimas:** apoyarse en herramientas estándar del sistema base (`bash`, `nmcli`, `ip`, `ss`, `iw`, `systemd`, `flock`, `dnsmasq`).
- **Sin secretos en el repositorio:** jamás almacenar contraseñas Wi-Fi (PSK), claves SSH privadas, UUID reales sensibles, direcciones MAC personales ni archivos `.env` reales en el código o la documentación pública.
- **Preservación:** no inventar contenidos de archivos del host no inspeccionados (como `~/start-vnc.sh` o reglas de firewall no verificadas).

---

## 4. Rigor técnico, pruebas y documentación

- **Distinción obligatoria de estados:** separar con claridad entre:
  - Código o documentación **desarrollado/implementado** en el repositorio (`IMPLEMENTED`).
  - Software **desplegado** en el sistema real.
  - Comportamiento **validado** mediante pruebas físicas en la Raspberry Pi 5 (`CONFIRMED`).
- **Prohibido inventar resultados:** nunca fabricar salidas de comandos ni atribuir al hardware real resultados obtenidos mediante simulaciones o *mocks*.
- **Actualizar la documentación siempre que cambie algo:** cualquier modificación de scripts, servicios, arquitectura o perfiles debe reflejarse en `docs/TECHNICAL_CONTEXT.md`, `CHANGELOG.md` y los documentos afectados.
- **Registrar decisiones significativas:** cambios estructurales o de diseño de red deben quedar documentados mediante un ADR en `docs/decisions/`.
- **Auditorías inmutables:** no sobrescribir archivos de auditorías históricas en `docs/audits/`; cada nueva auditoría se guarda en un nuevo archivo fechado.

---

## 5. Reporte obligatorio al finalizar cada tarea

Al concluir cualquier intervención, el agente debe informar de manera precisa y verificable:

1. Archivos creados o modificados.
2. Pruebas y validaciones efectivamente ejecutadas (distinguiendo entre estáticas, simuladas con *mocks* y reales en hardware).
3. Resultados reales observados.
4. Problemas, limitaciones o bloqueos detectados.
5. Próximos pasos recomendados (y comandos pendientes si aplica despliegue en Raspberry Pi).
