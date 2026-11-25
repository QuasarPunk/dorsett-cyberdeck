# Lista de Materiales (BOM) — Proyecto Dorsett

Este documento inventaría los componentes de hardware del Proyecto Dorsett indicando su estado de verificación. No incluye especificaciones eléctricas ni modelos mecánicos no confirmados.

---

## 1. Hardware confirmado y reportado (Estación base actual)

| Categoría | Componente | Especificación confirmada / reportada | Rol | Estado |
| :--- | :--- | :--- | :--- | :--- |
| **Cómputo (SBC)** | Raspberry Pi 5 | Arquitectura ARM64, Wi-Fi integrado (`wlan0`), Ethernet (`eth0`) | Unidad central, servidor headless, AP nómada y NAS | `CONFIRMED` |
| **Terminal / Pantalla** | Tablet X-View Quantum Carbono | Sistema operativo Windows 8.1 de 32 bits, cliente TightVNC Viewer | Pantalla táctil remota y cliente SMB | `REPORTED` |
| **Entrada de texto** | Teclado ultracompacto Noga | Formato compacto (reportado en README previo) | Entrada principal de comandos y texto | `REPORTED` |
| **Dispositivo apuntador** | Mouse óptico Noga | Mouse óptico | Navegación en entorno gráfico | `REPORTED` |
| **Red móvil / Cliente** | Smartphone Samsung Galaxy A10 | Hotspot Wi-Fi portátil y cliente LAN | Provisión de modo `MOBILE` y cliente de pruebas | `REPORTED` |
| **Estación auxiliar** | PC de escritorio | Estación de desarrollo principal | Desarrollo, administración SSH y VNC | `REPORTED` |

---

## 2. Hardware de expansión en planificación (`PLANNED`)

| Categoría | Componente previsto | Propósito previsto | Estado |
| :--- | :--- | :--- | :--- |
| **Coprocesador I/O** | Arduino UNO | Lectura de sensores y control de actuadores | `PLANNED` |
| **Alimentación portátil** | Módulo de baterías / UPS y regulación DC | Autonomía energética real fuera de red eléctrica (`v0.9.0`) | `PLANNED` |
| **Chasis y térmica** | Carcasa modular impresa en 3D y disipación activa | Integración mecánica y estabilidad térmica (`v0.8.0`) | `PLANNED` |
| **Autenticación física** | Lector NFC/RFID (ej. PN532) | Desbloqueo físico y control de montaje cifrado | `PLANNED` |
| **Segunda radio Wi-Fi** | Adaptador Wi-Fi USB adicional | Futuro modo `BRIDGE` simultáneo cliente + AP | `PLANNED` |

---

## 3. Notas de trazabilidad

- Los detalles exactos de RAM de la Raspberry Pi 5, almacenamiento (microSD/NVMe), fuente de alimentación actual y versión exacta del hardware inalámbrico integrado deberán registrarse tras ejecutar `software/scripts/collect-diagnostics.sh` y completar una inspección física.
- Las carpetas `hardware/models/` y `hardware/schematics/` se mantienen vacías con `.gitkeep` hasta disponer de diseños reales verificados.
