# Seguridad y Recuperación — Proyecto Dorsett

Este documento establece los controles de seguridad obligatorios para operar Dorsett de manera segura en entornos domésticos (`HOME`), móviles (`MOBILE`) y autónomos (`NOMAD`).

---

## 1. Seguridad inalámbrica y de perfiles

- **WPA2-PSK obligatorio en `NOMAD`:** `Dorsett-AP` debe utilizar `wifi-sec.key-mgmt wpa-psk`, protocolo `rsn` y cifrado `ccmp`. **Nunca configurar un Access Point abierto.**
- **Contraseña robusta:** utilizar una clave aleatoria o frase de paso de al menos 12–16 caracteres (mínimo técnico WPA2: 8).
- **Protección de credenciales:**
  - Las contraseñas Wi-Fi residen exclusivamente en los perfiles protegidos de `NetworkManager` (`/etc/NetworkManager/system-connections/`, permisos `0600` `root:root`).
  - Nunca guardar contraseñas en `/etc/dorsett/network.env`, en scripts, en argumentos de línea de comandos visibles ni en el repositorio Git.
- **Sin autoconexión a redes no autorizadas:** auditar periódicamente `nmcli -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show` y deshabilitar o eliminar perfiles desconocidos o no autorizados tras verificar su origen (pendiente confirmar el perfil secundario 2.4 GHz observado el `2026-11-24`).

---

## 2. Seguridad de servicios expuestos

### SSH (TCP `22`)

- Migrar progresivamente de autenticación por contraseña a **claves SSH (`ed25519`)**, manteniendo acceso de respaldo verificado antes de deshabilitar contraseñas en `/etc/ssh/sshd_config`.

### WayVNC (TCP `5900` y `5901`) y TightVNC en Windows 8.1

- **Auditoría pendiente (`UNKNOWN`):** verificar el archivo de configuración de `WayVNC` para confirmar que requiere autenticación por contraseña/usuario y revisar qué nivel de cifrado soporta **TightVNC Viewer** en Windows 8.1 de 32 bits.
- **Limitación conocida:** algunos clientes VNC antiguos no soportan TLS/VeNCrypt completo o utilizan esquemas débiles; por ello, es crítico que la capa Wi-Fi (`WPA2-CCMP`) esté cifrada y no exponer nunca el puerto `5901` ni `5900` fuera de la LAN confiable.

### Samba (TCP `445`)

- Revisar `/etc/samba/smb.conf` para:
  - **Deshabilitar SMB1 (`NT1`)** explícitamente (`server min protocol = SMB2` o superior compatible con Windows 8.1, que soporta SMB 2.1 / SMB 3.0).
  - Restringir acceso mediante usuarios dedicados (`valid users`) y permisos mínimos en `~/compartido`.
  - Evitar accesos anónimos (`guest ok = no`).

---

## 3. Consideraciones por uso de Windows 8.1 (Tablet X-View)

- **Windows 8.1 de 32 bits** se encuentra fuera de soporte de actualizaciones regulares de seguridad.
- **Controles obligatorios:**
  - Mantener la Tablet únicamente dentro de la intranet privada de Dorsett (`HOME` aislado o `NOMAD`), minimizando su navegación directa por Internet.
  - No almacenar claves administrativas maestras sin protección en la Tablet.
  - No exponer servicios de la Tablet ni de la Raspberry Pi a Internet.

---

## 4. Superficie de red y firewall

- **Prohibido exponer Dorsett directamente a Internet:** no configurar *port forwarding* en el router doméstico hacia los puertos `22`, `445`, `5900` o `5901`.
- **Revisión pendiente de firewall:** inspeccionar reglas activas (`nftables`/`iptables`/`ufw`). Si se habilita un firewall en la Raspberry Pi, asegurarse de no bloquear:
  - SSH (`22/tcp`), WayVNC (`5900/tcp`, `5901/tcp`), Samba (`445/tcp`) en las subredes privadas previstas (`192.168.1.0/24`, `10.42.0.0/24`, subred móvil).
  - Tráfico DHCP (`67/udp`) y DNS (`53/udp,tcp`) requerido por `dnsmasq` bajo `ipv4.method shared` en `wlan0`.

---

## 5. Integridad de ejecución y privilegios

- El servicio `dorsett-fallback.service` corre como `root`. Por ello:
  - Los ejecutables deben residir en `/usr/local/bin` y `/usr/local/sbin` propiedad de `root:root` (`0755`), **nunca** apuntando a clones de usuario ni repositorios en `/home/`.
  - `/etc/dorsett/network.env` debe tener permisos `0600` (`root:root`) y se parsea de forma segura como pares `CLAVE=VALOR` sin `eval` ni ejecución arbitraria de código.
- `collect-diagnostics.sh` opera en solo lectura, nunca usa `nmcli --show-secrets` y sanitiza MACs, UUIDs, nombres personales de redes e IPs públicas por defecto.

---

## 6. Requisitos obligatorios del mecanismo de recuperación remota

Toda transición manual de red solicitada desde una sesión remota (SSH/VNC) en una Raspberry Pi *headless* debe cumplir estas siete garantías:

1. **Conocer el perfil operativo previo:** capturar exactamente el nombre del perfil activo antes de conmutar.
2. **Poder restaurarlo:** reactivar el perfil anterior (o ejecutar *fallback*) de forma determinista.
3. **Independencia de la sesión SSH:** ejecutarse mediante temporizador del gestor `systemd` (`systemd-run --on-active=...`) para sobrevivir al cierre de la sesión SSH.
4. **Cero dependencia de Internet:** operar completamente en local mediante `nmcli`.
5. **Reversión automática ante fallo:** si el operador no confirma acceso en el plazo fijado, restaurar la conectividad original automáticamente.
6. **Cancelación únicamente explícita:** el operador debe ejecutar `dorsett-network confirm` tras comprobar acceso real desde otro dispositivo.
7. **Sin autocancelación engañosa:** jamás cancelar la recuperación solo porque `wlan0` haya tomado la IP `10.42.0.1` localmente; el criterio válido es la conectividad comprobada desde un cliente.
