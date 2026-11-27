# Proyecto Dorsett — CyberDeck Modular y Ecosistema LAN Offline

> *"La cyberdeck representa soberanía tecnológica aplicada: una herramienta reparable, entendible, expandible, autónoma y alineada con necesidades reales."*

**Proyecto Dorsett** (`dorsett-cyberdeck`) es una CyberDeck modular basada en **Raspberry Pi 5**, perteneciente al ecosistema tecnológico **QuasarPunk**. Está concebida como una computadora portátil reparable, autónoma, expandible y orientada a la soberanía tecnológica, con operación *offline-first*.

Más allá de actuar como estación personal portátil y servidor Linux *headless*, Dorsett opera como nodo central de control, telemetría, administración remota y almacenamiento NAS (Samba) para proyectos de robótica móvil, mecatrónica, hidroponía automatizada (**GreenNode**) e inteligencia artificial local (**Scio**).

---

## Filosofía y objetivos

### Principios de desarrollo

- **Offline-first:** operación completa en red local sin dependencia de Internet ni servicios en la nube.
- **Modularidad y reparabilidad:** arquitectura desacoplada de hardware y software fácil de mantener e inspeccionar.
- **Software libre y reproducibilidad:** herramientas estándar de Linux, NetworkManager y systemd, con documentación continua.
- **Compatibilidad con hardware reutilizado:** soporte para terminales existentes, como tabletas con Windows 8.1 de 32 bits vía TightVNC.
- **Desarrollo incremental basado en pruebas reales:** ninguna funcionalidad se declara validada en producción sin verificación física sobre la Raspberry Pi 5.

### Objetivos principales

- Consolidar una infraestructura LAN autónoma sin requerir salida a Internet.
- Mantener acceso remoto confiable mediante SSH, WayVNC y Samba desde tablet, PC de escritorio y smartphone.
- Incorporar conectividad resiliente en tres modos (`HOME`, `MOBILE` y `NOMAD`) con conmutación controlada y respaldo al arrancar (*v0.4.0 — Nomad Update*, validada físicamente en sus características principales).
- Separar explícitamente la **autonomía de red** (validada en `v0.4.0`) de la **autonomía energética** (planificada para etapas posteriores con baterías y gestión de energía).

---

## Características actuales

- **Acceso remoto por terminal:** servicio `ssh` activo en el puerto TCP `22`.
- **Escritorio remoto Wayland/labwc:** servicio de usuario `wayvnc-lan.service` en el puerto TCP `5901` (compatible con TightVNC en Windows 8.1 de 32 bits), preservando la instancia secundaria en el puerto TCP `5900`.
- **Almacenamiento local NAS:** servidor `smbd` (Samba) en el puerto TCP `445` compartiendo el directorio de usuario configurado (`~/compartido`).
- **Descubrimiento mDNS:** `avahi-daemon` activo para resolución local (`.local`), manteniendo la conexión por IP como método de referencia.
- **Priorización de red doméstica:** `NetworkManager` activo con prioridad máxima (`100`) para el perfil autorizado de red local.
- **Infraestructura Nomad Update (`v0.4.0`):** scripts `dorsett-network`, `setup-hotspot`, `collect-diagnostics`, unidad `dorsett-fallback.service` y plan de pruebas simuladas desplegados y validados en Raspberry Pi 5 en sus funciones principales.

---

## Inventario de hardware

| Componente | Modelo / Referencia | Rol en el sistema | Estado |
| :--- | :--- | :--- | :--- |
| **SBC principal** | Raspberry Pi 5 (ARM64) | Cómputo central, servidor *headless* y NAS | Confirmado (operativo) |
| **Terminal remoto** | Tablet X-View Quantum Carbono (Windows 8.1 32-bit) | Pantalla remota y control táctil vía TightVNC | Reportado (operativo) |
| **Teclado** | Teclado ultracompacto Noga | Entrada de texto | Reportado (operativo) |
| **Mouse** | Mouse óptico Noga | Dispositivo apuntador | Reportado (operativo) |
| **Smartphone** | Samsung Galaxy A10 | Hotspot móvil (`MOBILE`) y cliente LAN | Reportado (operativo) |
| **Estación de desarrollo** | PC de escritorio | Desarrollo, administración SSH y monitoreo | Reportado (operativo) |
| **Coprocesador I/O** | Arduino UNO | Futuras funciones de entrada/salida y sensores | Planificado |
| **Alimentación portátil** | Sistema de batería y gestión energética | Autonomía eléctrica móvil | Planificado |

Para el detalle completo de estado y verificación, consultar [docs/TECHNICAL_CONTEXT.md](docs/TECHNICAL_CONTEXT.md) y [hardware/BOM.md](hardware/BOM.md).

---

## Arquitectura general y modos de conectividad

Dorsett utiliza `NetworkManager` como único gestor de red y organiza la conectividad inalámbrica (`wlan0`) en **tres modos oficiales**, evitando ejecutar cliente y Access Point simultáneamente en la misma radio en esta versión:

| Modo | Rol de `wlan0` | Prioridad / Activación | Direccionamiento típico | Propósito |
| :--- | :--- | :--- | :--- | :--- |
| **`HOME`** | Cliente Wi-Fi | Autoconexión, prioridad `100` | DHCP en LAN doméstica (ej. `192.168.1.x`) | Desarrollo, acceso local completo y sincronización opcional |
| **`MOBILE`** | Cliente Wi-Fi | Autoconexión, prioridad `50` | DHCP del hotspot del smartphone | Operación en campo vinculada al teléfono |
| **`NOMAD`** | Access Point (`Dorsett-AP`) | Sin autoconexión; activación manual o *fallback* al arrancar | `10.42.0.1/24` (`ipv4.method shared` + `dnsmasq`) | Autonomía de red total sin router externo ni Internet |

```mermaid
flowchart TD
    Boot["Arranque Raspberry Pi 5 (Debian 13 ARM64)"] --> NM["NetworkManager inicia (ventana inicial ~30s)"]
    NM --> Check{"¿wlan0 conectado a perfil autorizado?"}
    Check -- "Perfil HOME (prio 100)" --> Home["Modo HOME: mantener red doméstica"]
    Check -- "Perfil MOBILE (prio 50)" --> Mobile["Modo MOBILE: mantener hotspot móvil"]
    Check -- "Perfil desconocido activo" --> Unknown["Preservar conexión y registrar advertencia"]
    Check -- "Sin conexión Wi-Fi válida" --> Nomad["Modo NOMAD: activar Dorsett-AP (10.42.0.1/24)"]
    Home --> Services["Servicios activos: SSH :22 | WayVNC :5901 | Samba :445"]
    Mobile --> Services
    Nomad --> Services
    Services --> Clients["Clientes: Tablet Win 8.1 (TightVNC/SMB) | PC | Smartphone | Nodos IoT"]
```

---

## Estado de implementación

| Capacidad / Versión | Estado actual | Observaciones |
| :--- | :--- | :--- |
| **v0.1.0 — Remote Access Foundation** | Confirmado en hardware | SSH (`22`), WayVNC (`5900`/`5901`), `wayvnc-lan.service` y acceso desde Tablet Windows 8.1 |
| **v0.2.0 — Local Network Ecosystem** | Confirmado / Reportado | Samba (`445`) operativo sobre directorio compartido e integración multi-dispositivo |
| **v0.3.0 — Network Stability** | Confirmado en auditoría | Priorización del perfil doméstico (`100`) y auditoría del sistema (2026-11-24) |
| **v0.4.0 — Nomad Update (Red)** | Validada en hardware (características principales) | `HOME` y `NOMAD` operativos, incluido arranque autónomo; `MOBILE` pendiente. Auditoría: [2026-11-26-nomad-deployment.md](docs/audits/2026-11-26-nomad-deployment.md) |
| **Autonomía energética** | Planificado | Pendiente de diseño de alimentación por baterías y gestión térmica (etapas v0.8.0–v0.9.0) |

> **Nota importante sobre autonomía:** la actualización `v0.4.0` resuelve la **autonomía de red** (operar sin router externo), pero la **autonomía energética** de la CyberDeck sigue pendiente de implementación física.

### Estado funcional de `v0.4.0`

- **`HOME`:** operativo y reconocido correctamente.
- **`NOMAD`:** operativo, incluido el arranque autónomo sin router.
- **`MOBILE`:** pendiente de configuración del perfil y validación; el Galaxy A10 fue validado como cliente de NOMAD.
- **Recuperación temporizada:** comprobada físicamente en la prueba NOMAD de 300 segundos.
- **Regreso a HOME:** comprobado en pruebas anteriores.
- **Regreso manual desde NOMAD tras el arranque aislado:** pendiente de confirmación específica.
- **Recuperación dinámica ante caídas durante la ejecución:** no implementada.
- **Interfaz gráfica:** pendiente.

#### Manual rápido de comandos

```bash
sudo dorsett-network status
sudo dorsett-network --rollback-seconds 300 home
sudo dorsett-network --rollback-seconds 300 nomad
sudo dorsett-network confirm
```

La conmutación interrumpe momentáneamente la conexión: el temporizador de reversión permite recuperar el modo anterior si la nueva red no funciona. **Confirma solo después de verificar el acceso desde un cliente conectado a la nueva red**, ejecutando `sudo dorsett-network confirm` para cancelar la reversión automática.

Cuando NOMAD reaparece con el router doméstico, Dorsett **no retorna automáticamente a HOME**: el comportamiento es intencional para no cortar sesiones SSH o TightVNC activas. El regreso se realiza manualmente o tras un nuevo arranque.

#### Acceso en NOMAD

| Servicio | Desde la red `Dorsett-AP` |
| :--- | :--- |
| SSH | `ssh <usuario>@10.42.0.1` |
| TightVNC Viewer | `10.42.0.1::5901` |
| Samba (Windows) | `\\10.42.0.1` con el usuario y la contraseña Samba configurados en el sistema |

La Tablet Windows 8.1 con TightVNC constituye actualmente una **solución de visualización provisional**, no una pantalla integrada definitiva.

---

## Estructura del repositorio

```text
dorsett-cyberdeck/
├── README.md                              # Visión general y navegación del proyecto
├── AGENTS.md                              # Reglas permanentes para agentes de IA y colaboradores
├── CHANGELOG.md                           # Registro histórico de hitos y cambios
├── ROADMAP.md                             # Planificación evolutiva por versiones
├── LICENSE                                # Propuesta de licencia MIT para software
├── .gitignore                             # Exclusiones de secretos, logs e informes locales
├── docs/
│   ├── TECHNICAL_CONTEXT.md               # Memoria técnica viva del sistema
│   ├── ARCHITECTURE.md                    # Arquitectura integral de hardware y software
│   ├── NETWORKING.md                      # Diseño detallado de modos HOME, MOBILE y NOMAD
│   ├── INSTALLATION.md                    # Procedimiento de despliegue controlado y recuperación
│   ├── TROUBLESHOOTING.md                 # Incidencias conocidas y guías de diagnóstico
│   ├── SECURITY.md                        # Política de seguridad y hardening
│   ├── decisions/
│   │   └── ADR-001-network-modes.md       # Decisión arquitectónica sobre modos de red
│   ├── audits/
│   │   ├── 2026-11-24-system-audit.md     # Registro histórico de la auditoría técnica
│   │   └── 2026-11-26-nomad-deployment.md # Despliegue físico NOMAD validado por el propietario
│   └── development/
│       └── HANDOFF.md                     # Registro de cierre y transferencia
├── software/
│   ├── scripts/
│   │   ├── dorsett-network.sh             # CLI de gestión de red y fallback
│   │   ├── setup-hotspot.sh               # Configuración segura del perfil Dorsett-AP
│   │   └── collect-diagnostics.sh         # Recopilación sanitaria de diagnósticos
│   ├── systemd/
│   │   └── dorsett-fallback.service       # Unidad systemd de respaldo al arranque
│   └── config/
│       └── network.env.example            # Plantilla de configuración local
├── tests/
│   ├── network-test-plan.md               # Matriz de escenarios T01–T19
│   └── test-network.sh                    # Suite automatizada con mocks de nmcli
├── firmware/                              # Reservado para futuros firmwares (Arduino / MCU)
├── hardware/
│   ├── models/                            # Reservado para futuros modelos 3D
│   ├── schematics/                        # Reservado para futuros esquemas eléctricos
│   └── BOM.md                             # Inventario de materiales (confirmado y planificado)
└── assets/
    ├── images/                            # Recursos visuales del proyecto
    └── diagrams/                          # Diagramas complementarios
```

---

## Navegación por la documentación

1. Si eres nuevo en el proyecto o colaboras con asistencia automatizada, lee primero [AGENTS.md](AGENTS.md) y la memoria técnica en [docs/TECHNICAL_CONTEXT.md](docs/TECHNICAL_CONTEXT.md).
2. Para comprender el diseño del sistema y las decisiones tomadas, consulta [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/NETWORKING.md](docs/NETWORKING.md) y [docs/decisions/ADR-001-network-modes.md](docs/decisions/ADR-001-network-modes.md).
3. Antes de desplegar cambios en la Raspberry Pi 5 real, revisa [docs/SECURITY.md](docs/SECURITY.md), [docs/INSTALLATION.md](docs/INSTALLATION.md) y [tests/network-test-plan.md](tests/network-test-plan.md).
4. Si encuentras anomalías (como advertencias en WayVNC o problemas de DHCP), consulta [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) y ejecuta `software/scripts/collect-diagnostics.sh`.

## Instalación en Raspberry Pi

Desde la raíz de la copia del repositorio en la Pi, ejecuta `bash install.sh --check` y luego `sudo bash install.sh`. Configura el perfil HOME local y valida el AP con recuperación temporizada antes de habilitar el fallback. El procedimiento quedó validado físicamente por el propietario el 26 de noviembre de 2026. [Guía de instalación y prueba](docs/INSTALLATION.md)

---

## Roadmap resumido

- **v0.1.0 – v0.3.0:** acceso remoto (SSH/WayVNC), NAS Samba y estabilidad de perfil doméstico *(completado)*.
- **v0.4.0 — Nomad Update:** modos `HOME`/`NOMAD` y *fallback* al arranque *(validado en hardware)*; `MOBILE` queda pendiente.
- **v0.5.0 – v0.6.0:** recuperación dinámica ante caídas de red e interfaz gráfica de administración *(pendiente)*.
- **v0.7.0 – v1.0.0:** nodos IoT y robótica, chasis modular con disipación térmica, pantalla HDMI directa y alimentación por baterías *(objetivos futuros)*.
- **Integración futura con Scio Control Center**, inicialmente alojado en Dorsett como proyecto de software independiente.

Consulta el detalle completo en [ROADMAP.md](ROADMAP.md) y el historial en [CHANGELOG.md](CHANGELOG.md).

---

## Relación con Scio

Dorsett es la **plataforma física y operativa**: una CyberDeck modular, autónoma y experimental. **Scio Control Center** será un proyecto de software independiente, inicialmente alojado en Dorsett; no se incorpora código de Scio a este repositorio.

Entre los objetivos futuros se encuentran la integración con Scio Control Center, la administración gráfica de conectividad, una pantalla HDMI directa para reducir la dependencia de VNC, la integración de dispositivos IoT y robótica, y la alimentación portátil.

---

## Licencia y organización

Proyecto desarrollado dentro del ecosistema **QuasarPunk**.
El código y la documentación de este repositorio cuentan con una propuesta de licencia **MIT** en [LICENSE](LICENSE), pendiente de confirmación formal del titular de derechos. La licencia aplicable a futuros diseños físicos de hardware se definirá cuando existan artefactos publicados.
