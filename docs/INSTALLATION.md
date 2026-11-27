# Instalación controlada de Dorsett v0.4.0

La instalación se realiza sobre Debian 13 ARM64 con NetworkManager activo. La plataforma de referencia es Raspberry Pi 5 con Debian 13.6 y NetworkManager 1.52.1. Antes de cambiar de modo, comprueba un acceso de rescate por Ethernet independiente de `wlan0` o una consola física. Mantén el router HOME disponible durante toda la prueba manual.

## 1. Instalar desde la copia del repositorio

Copia a la Pi la revisión que contiene `install.sh` y abre una terminal en la raíz de esa copia. Desde allí ejecuta:

```bash
bash install.sh --check
sudo bash install.sh
sudoedit /etc/dorsett/network.env
```

El instalador comprueba la plataforma, las herramientas requeridas y el soporte AP de `wlan0`. Copia los scripts y la unidad como `root:root`, preserva el contenido de una configuración existente con permisos `0600` y recarga las definiciones de systemd. La conexión activa y el estado de habilitación del servicio se conservan.

Durante el despliegue real, la consulta original de perfiles con columnas `AUTOCONNECT` falló; el propietario la sustituyó por `PAGER=cat LC_ALL=C timeout 10s nmcli -f NAME,TYPE,DEVICE connection show` y la instalación terminó correctamente. La causa exacta del fallo no quedó determinada.

Toma de la lista `NAME,TYPE,DEVICE` que imprime el instalador el nombre exacto del perfil HOME (Wi-Fi). Si necesitas confirmar su prioridad `100`, consúltala con `nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show`. El perfil de referencia tiene el prefijo `netplan-wlan0-`. Sustituye `home-profile` en `HOME_PROFILE="home-profile"` por ese nombre, manteniendo las comillas. Deja `MOBILE_PROFILE=""` hasta registrar el hotspot del teléfono. Guarda únicamente valores de configuración. La contraseña WPA2 se configura por separado en NetworkManager.

Comprueba que `detected_mode=HOME`, que `wlan0` tiene IPv4, que la subred `10.42.0.0/24` está libre y que los servicios escuchan en direcciones accesibles desde el AP. En una primera instalación, verifica que la unidad figura como `disabled`.

```bash
sudo dorsett-network status
ip -4 addr show
ip -4 route show table all
sudo ss -lnt '( sport = :22 or sport = :5901 or sport = :445 )'
systemctl is-enabled dorsett-fallback.service
```

## 2. Crear y proteger el AP sin activarlo

```bash
sudo /usr/local/sbin/dorsett-setup-hotspot --dry-run
sudo /usr/local/sbin/dorsett-setup-hotspot
nmcli -f connection.autoconnect,802-11-wireless.mode,802-11-wireless.band,ipv4.method,ipv4.addresses,802-11-wireless-security.key-mgmt,802-11-wireless-security.proto connection show id Dorsett-AP
```

Introduce y confirma la contraseña en el aviso oculto del script. Si ya existe un perfil incompleto, usa `sudo /usr/local/sbin/dorsett-setup-hotspot --update` mientras estés en HOME. Comprueba `autoconnect=no`, modo `ap`, banda `bg`, IPv4 `shared` con `10.42.0.1/24`, WPA2 (`wpa-psk`, `rsn`, `ccmp`) y `802-11-wireless-security.wps-method=1` (WPS deshabilitado). El script aplica esta propiedad tanto al crear el perfil como al actualizar uno existente, incluso sin `--update`, y la verifica en la validación final.

En la prueba física, Windows pidió una entrada de ocho dígitos compatible con un PIN WPS; el propietario desactivó WPS con `sudo nmcli connection modify Dorsett-AP 802-11-wireless-security.wps-method 1` y las conexiones posteriores de Windows y Android fueron exitosas. No se afirma que WPS fuera la causa demostrada de todos los problemas iniciales.

## 3. Comprobar la recuperación mientras HOME sigue disponible

En una primera prueba, desde HOME y sin una transición pendiente, programa el mismo comando de recuperación que usa Dorsett. Cierra la sesión SSH después de comprobar que systemd lista el temporizador. Tras el vencimiento, vuelve a entrar por HOME y revisa el resultado.

```bash
sudo systemd-run --unit=dorsett-home-check --on-active=30s --timer-property=AccuracySec=1s /usr/local/bin/dorsett-network --config /etc/dorsett/network.env rollback
systemctl list-timers dorsett-home-check.timer --no-pager
```

```bash
sudo journalctl -u dorsett-home-check.service -b --no-pager
sudo dorsett-network status
```

Continúa cuando el diario confirme la restauración y el estado vuelva a mostrar HOME con IPv4. Si falla, revisa el nombre y la disponibilidad del perfil desde el acceso de rescate.

## 4. Validar NOMAD y regresar a HOME

Desde HOME, ejecuta lo siguiente. La opción explícita arma la reversión incluso si `sudo` elimina las variables SSH. El temporizador se programa antes de activar el AP y seguirá pendiente después de activarlo.

```bash
sudo dorsett-network --dry-run --rollback-seconds 300 nomad
sudo dorsett-network --rollback-seconds 300 nomad
```

Desde la Tablet, conéctate a `Dorsett-AP` e introduce la contraseña en el diálogo Wi-Fi. Ejecuta `ipconfig /all` y comprueba que DHCP asignó una dirección `10.42.0.x` con máscara `255.255.255.0`. Abre una sesión SSH al puerto 22 de `10.42.0.1` con tu usuario habitual, inicia una sesión TightVNC en `10.42.0.1::5901` y abre un archivo compartido en `\\10.42.0.1` desde el Explorador de Windows.

Si cualquiera de las comprobaciones falla, deja vencer el temporizador, vuelve a conectarte a HOME y consulta `sudo journalctl -u dorsett-network-rollback.service -b --no-pager`. Si la recuperación falla, usa el acceso de rescate. Si las tres aplicaciones y DHCP funcionan, ejecuta desde la sesión SSH de la Tablet al AP:

```bash
sudo dorsett-network status
systemctl list-timers dorsett-network-rollback.timer --no-pager
sudo dorsett-network confirm
```

Con el router disponible, vuelve a HOME manualmente. La segunda transición también queda protegida, esta vez con retorno a NOMAD si falla HOME. Reconecta el cliente al router, abre SSH por la dirección HOME y confirma antes del vencimiento.

```bash
# Desde NOMAD
sudo dorsett-network --rollback-seconds 300 home
# Desde la nueva sesión SSH en HOME
sudo dorsett-network status
sudo dorsett-network confirm
```

### Comandos de referencia para la conmutación

```bash
sudo dorsett-network status
sudo dorsett-network --rollback-seconds 300 home
sudo dorsett-network --rollback-seconds 300 nomad
sudo dorsett-network confirm
```

La conmutación interrumpe momentáneamente la conexión. Usa siempre una ventana de reversión y ejecuta `confirm` **solo después de verificar acceso desde un cliente conectado a la nueva red**; de lo contrario, el temporizador restaura el modo anterior. La reversión de 300 segundos quedó comprobada físicamente en la prueba NOMAD.

NOMAD no retorna automáticamente a HOME cuando reaparece el router; el comportamiento es intencional. El regreso manual desde NOMAD después del arranque aislado queda pendiente de confirmación específica. Resultados reales: [auditoría de despliegue](audits/2026-11-26-nomad-deployment.md).

## 5. Habilitar el fallback y probar un arranque aislado

Desde HOME, una vez validado el AP y el regreso manual, habilita la unidad para el siguiente arranque:

```bash
sudo systemctl enable dorsett-fallback.service
```

Comprueba que el acceso de rescate también funciona con el router apagado. Desde ese acceso, con el router y el hotspot del teléfono apagados, reinicia la Pi. Los temporizadores transitorios de la prueba anterior terminan al reiniciar.

```bash
sudo systemctl reboot
```

Espera el arranque y la ventana inicial de 30 segundos. Desde la Tablet repite DHCP, SSH, TightVNC y Samba sobre el AP. Desde la Pi comprueba:

```bash
sudo dorsett-network status
systemctl status dorsett-fallback.service --no-pager
sudo journalctl -u dorsett-fallback.service -b --no-pager
```

Espera `detected_mode=NOMAD`, `10.42.0.1/24` y una unidad `active (exited)` tras una única activación correcta. Vuelve a encender el router y verifica que la sesión NOMAD sigue accesible antes de regresar a HOME. Si falla el arranque aislado, enciende el router y usa el acceso de rescate para ejecutar `sudo systemctl disable dorsett-fallback.service` y `sudo dorsett-network home`.

## Cómo selecciona el fallback

NetworkManager decide qué perfil cliente autoconectar. El servicio observa `wlan0` durante una ventana acotada y conserva HOME, MOBILE o cualquier conexión cliente desconocida en estado conectado con IPv4 distinta de `169.254.0.0/16` y `0.0.0.0/8`. La conexión desconocida queda registrada con una advertencia. Un perfil secundario autoconectado con IPv4 puede impedir NOMAD aunque estén apagados el router HOME y el teléfono. Antes del reinicio de prueba, revisa qué otras redes guardadas pueden estar al alcance.

Una conexión sin IPv4 utilizable sigue dentro de la ventana de espera. Al vencer, el servicio puede reemplazarla activando `Dorsett-AP`. La selección usa estado local y direccionamiento, sin pruebas de Internet, DNS o gateway. El servicio es `oneshot`, conserva un NOMAD ya operativo y termina tras una única decisión. Volver a HOME requiere intervención manual o un nuevo arranque.
