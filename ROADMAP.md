# Hoja de Ruta (Roadmap) — Proyecto Dorsett

> **Aviso de planificación:** las versiones descritas a continuación representan la evolución planificada del Proyecto Dorsett. No constituyen compromisos con fechas fijas ni implican que las capacidades futuras estén implementadas o validadas en hardware real.

---

## Etapas históricas y en curso

### v0.1.0 — Acceso remoto *(Confirmado / Reportado)*

- Base de sistema operativo Linux ARM64 en Raspberry Pi 5.
- Administración remota por SSH (TCP `22`).
- Escritorio remoto WayVNC en TCP `5901` compatible con TightVNC en Tablet Windows 8.1 de 32 bits.
- Persistencia mediante servicio systemd de usuario (`wayvnc-lan.service`).

### v0.2.0 — Ecosistema LAN y NAS *(Confirmado / Reportado)*

- Servidor local Samba (`smbd`, TCP `445`) con directorio compartido.
- Integración operativa entre Raspberry Pi 5, PC de escritorio, Tablet Windows 8.1 y smartphone Android en intranet local sin Internet.

### v0.3.0 — Estabilidad de red *(Confirmado en auditoría del 2026-11-24)*

- Auditoría de perfiles de `NetworkManager`.
- Priorización del perfil doméstico (`autoconnect-priority = 100`).
- Estabilización de acceso local mediante IP `192.168.1.52/24`.

### v0.4.0 — Nomad Update y fallback al arrancar *(En desarrollo — Implementado en repositorio, pendiente de validación física)*

- Reestructuración documental y técnica del repositorio.
- Arquitectura formal de modos `HOME`, `MOBILE` y `NOMAD` (`Dorsett-AP`, `10.42.0.1/24`).
- Scripts de gestión de red, aprovisionamiento del AP y diagnóstico sanitizado.
- Unidad `dorsett-fallback.service` al arranque (sin escaneo continuo ni retorno automático).
- Procedimiento de recuperación segura para sesiones remotas y plan de pruebas T01–T19.

---

## Etapas futuras planificadas

### v0.5.0 — Recuperación dinámica ante caídas de red *(Planificado)*

- Mecanismos controlados de detección y recuperación ante pérdida de enlace sin interrumpir sesiones activas de forma abrupta.
- Políticas configurables de reintento y transición segura entre perfiles.

### v0.6.0 — Interfaz gráfica de administración *(Planificado)*

- Panel ligero (local o web en LAN) para visualizar estado de red, servicios, temperaturas y conmutar modos de conectividad sin usar terminal.

### v0.7.0 — Integración de nodos IoT *(Planificado)*

- Enlace de telemetría y control con nodos externos de **QuasarPunk**:
  - **GreenNode:** estación de hidroponía automatizada.
  - **Plataformas robóticas móviles y mecatrónicas.**
  - Coprocesador de entrada/salida mediante **Arduino UNO** (o microcontroladores complementarios).

### v0.8.0 — Prototipo de chasis y gestión térmica *(Planificado)*

- Modelado 3D e impresión de carcasa modular reparable.
- Diseño de flujo de aire y disipación térmica activa para la Raspberry Pi 5.

### v0.9.0 — Alimentación portátil y gestión energética *(Planificado)*

- Integración de banco de baterías / UPS portátil con monitoreo de carga y apagado seguro.
- Distinción efectiva entre autonomía de red y autonomía energética sostenida.

### v1.0.0 — CyberDeck modular funcional y autónoma *(Planificado)*

- Consolidación de hardware, chasis, alimentación portátil, interfaz de usuario, red nómada y enlace con periféricos en una unidad completa y reproducible.

---

## Hitos posteriores y líneas de investigación *(Largo plazo)*

- **IA local con Ollama:** ejecución de modelos de lenguaje locales sin dependencia de la nube.
- **Síntesis de voz Piper TTS:** salida de audio offline para asistencia interactiva.
- **Asistente Scio:** integración conversacional local orientada a operación técnica y telemetría.
- **Autenticación física NFC/RFID:** control de acceso por hardware (por ejemplo, lector `PN532`).
- **Almacenamiento cifrado:** protección de datos en reposo (por ejemplo, volúmenes cifrados LUKS).
- **Modo `BRIDGE` multi-radio:** incorporación de un segundo adaptador Wi-Fi USB para operar simultáneamente como cliente de una red externa y Access Point local.
- **Integración multi-proyecto QuasarPunk:** interoperabilidad estándar entre Dorsett, GreenNode, robótica móvil y plataformas experimentales.
