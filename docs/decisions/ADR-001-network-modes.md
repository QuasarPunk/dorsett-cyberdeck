# ADR-001: Arquitectura de Modos de Red y Fallback Inicial (v0.4.0)

- **Estado:** Aceptado, implementado, desplegado y validado en sus características principales sobre Raspberry Pi 5 (`v0.4.0`). `MOBILE` y la matriz completa `T01`–`T19` siguen pendientes.
- **Fecha:** 2026-11-24.
- **Ámbito:** Gestión de conectividad inalámbrica en `wlan0` sobre Debian GNU/Linux 13 (`trixie` ARM64) con `NetworkManager 1.52.1`.

---

## 1. Contexto

El Proyecto Dorsett opera sobre una **Raspberry Pi 5 headless** (`raspi-ali`) cuya interfaz principal de interacción es remota: SSH (TCP `22`), WayVNC (TCP `5901` y `5900`) y Samba (TCP `445`), consumidos desde una Tablet Windows 8.1 de 32 bits (TightVNC), una PC de escritorio y un smartphone Samsung Galaxy A10.

Actualmente la conectividad depende de un router doméstico externo (`192.168.1.x`). Cuando la Raspberry Pi se traslada fuera de ese entorno o el router no está disponible, el equipo pierde conectividad en `wlan0` y queda inaccesible al no poseer pantalla ni teclado conectados permanentemente en operación móvil.

---

## 2. Problema

1. **Dependencia de infraestructura externa:** sin un router doméstico o un punto de acceso conocido, el usuario no puede conectarse a Dorsett por SSH, VNC ni Samba.
2. **Riesgo de bloqueo *headless*:** cualquier script o servicio de red que cambie perfiles sin control, que dependa de Internet para decidir conectividad o que interrumpa sesiones activas puede dejar la Raspberry Pi incomunicada.
3. **Interacción con perfiles previos:** la auditoría del `2026-11-24` reveló perfiles con prefijo `netplan-` y un perfil secundario de `2.4 GHz` con autoconexión habilitada cuya función aún no está confirmada.

---

## 3. Decisión

### 3.1 Gestor único: `NetworkManager`

Se adopta **`NetworkManager` (`1.52.1`)** como único gestor de conexiones, perfiles y prioridades. No se introducirá `hostapd` independiente ni un segundo demonio gestor que compita con `NetworkManager` sobre `wlan0`.

### 3.2 Arquitectura de tres modos oficiales

1. **`HOME`** (cliente Wi-Fi, `connection.autoconnect yes`, `autoconnect-priority 100`): conexión preferente a la red doméstica autorizada mediante DHCP (observado `192.168.1.52/24`). Internet es opcional.
2. **`MOBILE`** (cliente Wi-Fi, `connection.autoconnect yes`, `autoconnect-priority 50`): conexión al hotspot móvil del Samsung Galaxy A10 cuando `HOME` no está disponible. Internet es opcional; el perfil se registra interactivamente (`nmcli --ask`).
3. **`NOMAD`** (Access Point `Dorsett-AP`, `connection.autoconnect no`): `wlan0` pasa a modo `ap` (`802-11-wireless.mode ap`, banda `bg` 2.4 GHz, canal `6`, seguridad WPA2-PSK/CCMP, IPv6 deshabilitado) cuando no existe conectividad cliente autorizada al arrancar o cuando el operador lo solicita explícitamente.

### 3.3 Justificación de `ipv4.method shared`

El perfil `Dorsett-AP` utiliza `ipv4.method shared` con dirección explícita `10.42.0.1/24`. En `NetworkManager`, este método:

- Asigna automáticamente `10.42.0.1/24` a `wlan0` sin depender de un servidor DHCP externo.
- Lanza una instancia aislada de `/usr/sbin/dnsmasq` (ya instalado en el sistema) para entregar direcciones IP locales a los clientes conectados (Tablet X-View, PC, smartphone, nodos IoT) en `10.42.0.0/24`.
- Elimina la necesidad de configurar y mantener un servicio `isc-dhcp-server` o `dnsmasq` global independiente que podría entrar en conflicto con la operación en modos `HOME` o `MOBILE`.

### 3.4 Restricciones de concurrencia inalámbrica y exclusión de AP+Cliente simultáneo

Según `iw list` (`2026-11-24`), el controlador Wi-Fi soporta la combinación `1 managed + 1 AP` únicamente sobre **un canal compartido**. Sin embargo:

- La estabilidad concurrente de `managed + AP` en un mismo chip inalámbrico bajo carga VNC/Samba y distintos canales de routers externos no está validada experimentalmente.
- Si un router doméstico o hotspot móvil opera en un canal distinto o en 5 GHz, mantener un AP simultáneo en un único canal compartido introduce fallos de asociación o caídas de enlace.

Por ello, en `v0.4.0` se decide utilizar **conmutación excluyente** entre modo cliente (`HOME`/`MOBILE`) y modo Access Point (`NOMAD`).

### 3.5 Limitación del *fallback* únicamente al arranque en `v0.4.0`

El servicio `dorsett-fallback.service` actúa **una sola vez en el arranque** tras una ventana inicial acotada (~30 segundos):

- Si `HOME` o `MOBILE` están activos con IPv4 válida no *link-local*, los preserva.
- Si existe una conexión desconocida activa, la preserva y registra una advertencia sin desconectarla ni adoptarla.
- Solo si no hay conexión Wi-Fi válida tras la ventana de espera, activa `Dorsett-AP`.
- **No** realiza escaneos continuos en segundo plano ni vuelve automáticamente desde `NOMAD` hacia `HOME` si el router reaparece, evitando interrumpir abruptamente sesiones activas de TightVNC o SSH. El retorno a `HOME`/`MOBILE` en `v0.4.0` se realiza manualmente o mediante reinicio.

---

## 4. Alternativas consideradas

1. **`hostapd` + `dnsmasq` globales manuales:** descartado en `v0.4.0` por competir con `NetworkManager` sobre `wlan0` y aumentar la complejidad de transición entre cliente y AP.
2. **Concurrencia STA + AP en `wlan0` (`p2p` / interfaz virtual):** descartado hasta disponer de pruebas de estabilidad en hardware real, dada la restricción de un único canal compartido.
3. **Escaneo continuo y conmutación automática bidireccional:** diferido a `v0.5.0` por el riesgo de desconexión inesperada durante sesiones VNC/SSH en uso.
4. **Modo `BRIDGE` mediante segundo adaptador Wi-Fi USB:** considerado como la alternativa futura más limpia para operar simultáneamente como cliente (en una interfaz dedicada) y Access Point (en otra), sin restricciones de canal compartido.

---

## 5. Consecuencias

### Positivas

- Cero dependencia de Internet (sin `ping` a servidores externos ni consultas DNS públicas).
- Uso exclusivo de herramientas nativas de Debian 13 y `NetworkManager 1.52.1`.
- Arranque determinista y seguro para sesiones activas en modo `NOMAD`.
- Reversibilidad sencilla al mantener `NetworkManager` como única fuente de verdad.

### Limitaciones y riesgos

- En modo `NOMAD`, Dorsett no tiene acceso simultáneo a una red Wi-Fi externa salvo que se conecte Ethernet (`eth0`) o se añada un segundo adaptador inalámbrico en el futuro.
- El cambio manual remoto de modo por SSH corta la sesión si falla o cambia la subred; por ello exige un mecanismo de recuperación temporizada independiente de la sesión SSH.
- El funcionamiento real de `dnsmasq` bajo `ipv4.method shared` y el acceso desde Windows/Android a `Dorsett-AP` quedaron confirmados físicamente por el propietario el `2026-11-26`; la compatibilidad con la Tablet Windows 8.1 se confirmó al conectarla al AP.

---

## 6. Criterios de revisión futura

Este ADR deberá revisarse cuando se cumpla cualquiera de los siguientes hitos:

1. Validación física de `v0.4.0` mediante el plan de pruebas `T01`–`T19`: registrada parcialmente en [2026-11-26-nomad-deployment.md](../audits/2026-11-26-nomad-deployment.md), sin aprobar automáticamente todos los escenarios.
2. Diseño de recuperación dinámica ante caídas de red (`v0.5.0`).
3. Incorporación de un segundo adaptador Wi-Fi USB para habilitar un modo `BRIDGE` dedicado.
