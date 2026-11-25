# Guía de Resolución de Problemas — Proyecto Dorsett

Este documento recopila incidencias observadas y procedimientos de diagnóstico no destructivos para el Proyecto Dorsett.

---

## 1. Advertencia en WayVNC: `Output NOOP-1 power state failure`

- **Mensaje observado (`2026-11-24`):**
  `Warning: ../src/output.c:300: Output NOOP-1 power state failure.`
- **Estado:** incidencia observada (`CONFIRMED`), sin evidencia de bloqueo operativo en TCP `5901`.
- **Acción recomendada:** **no** modificar la configuración de `WayVNC` ni desactivar `wayvnc-lan.service` únicamente por esta advertencia. Si en el futuro provoca congelamientos de imagen o desconexiones reales:
  1. Inspeccionar `journalctl --user -u wayvnc-lan.service -n 100 --no-pager`.
  2. Revisar `~/start-vnc.sh` y `~/.config/systemd/user/wayvnc-lan.service` sin alterar el puerto `5901` ni la instancia en `5900`.

---

## 2. Pérdida de acceso tras cambiar manualmente de modo de red

- **Síntoma:** al ejecutar `dorsett-network nomad` o `home` por SSH, la sesión se congela y no responde.
- **Comportamiento esperado con protección activa:**
  - Si usaste la protección remota (`systemd-run`), espera a que expire `ROLLBACK_TIMEOUT` (por defecto `120` s o el valor indicado en `--rollback-seconds`). El sistema ejecutará `dorsett-network rollback` automáticamente y restaurará el perfil previo.
  - Si estás físicamente junto a la Raspberry Pi con teclado/monitor o consola serial, inspecciona:
    ```bash
    sudo systemctl status dorsett-network-rollback.timer dorsett-network-rollback.service --no-pager
    dorsett-network status
    ```

---

## 3. El AP `Dorsett-AP` arranca pero los clientes no reciben IP

- **Posibles causas:**
  1. `dnsmasq` no está disponible o falla al ser lanzado por NetworkManager (`ipv4.method shared`).
  2. Un servicio `dnsmasq` global independiente está ocupando el puerto `53` o `67` en `0.0.0.0`.
  3. Reglas de firewall (`nftables`/`iptables`/`ufw`) bloquean UDP `67` (DHCP) o UDP/TCP `53` en `wlan0`.
- **Diagnóstico read-only:**
  ```bash
  command -v dnsmasq
  systemctl is-active dnsmasq || true
  journalctl -u NetworkManager -n 80 --no-pager
  sudo ss -lunp | grep -E ':(53|67)\b' || true
  ```
- **Nota:** bajo `NetworkManager` `ipv4.method shared`, el servicio global `dnsmasq.service` normalmente debe permanecer deshabilitado/inactivo para no colisionar con la instancia que NetworkManager lanza por interfaz.

---

## 4. `raspi-ali.local` (mDNS) no resuelve desde Tablet Windows 8.1 o Android

- **Diagnóstico:** Windows 8.1 sin soporte Bonjour/mDNS nativo completo o ciertos clientes Android pueden no resolver `.local` en redes aisladas o en modo AP.
- **Solución operativa:** utilizar siempre la dirección IP como método de referencia:
  - En `HOME`: IP asignada (observada `192.168.1.52`).
  - En `NOMAD`: `10.42.0.1` (`10.42.0.1::5901` en TightVNC Viewer, `\\10.42.0.1` en el Explorador de Windows para Samba).

---

## 5. Perfiles duplicados o cambios revertidos por `netplan`

- **Síntoma:** aparecen múltiples perfiles con nombres similares o un cambio hecho con `nmcli` desaparece tras reiniciar cuando el perfil empieza por `netplan-`.
- **Diagnóstico:**
  ```bash
  ls -la /etc/netplan/
  nmcli -f NAME,UUID,FILENAME connection show
  ```
- **Acción:** no ejecutar `netplan apply` sin revisar primero los `.yaml`. Identificar qué archivo define el perfil doméstico antes de ajustar configuraciones permanentes.

---

## 6. Recopilación automática de diagnósticos

Para generar un informe Markdown completo, sanitizado y sin secretos para análisis o actualización de `TECHNICAL_CONTEXT.md`:

```bash
bash software/scripts/collect-diagnostics.sh
```

El informe se guardará por defecto en `docs/audits/local/` (excluido de Git).
