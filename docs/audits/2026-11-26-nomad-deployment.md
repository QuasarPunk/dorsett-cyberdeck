# Auditoría de Despliegue Físico NOMAD — 2026-11-26 / 2026-11-27

- **Fechas de las pruebas físicas:** 26 y 27 de noviembre de 2026.
- **Equipo:** Raspberry Pi 5 (ARM64), Debian GNU/Linux 13.6, NetworkManager 1.52.1.
- **Naturaleza de este registro:** transcripción estructurada de los resultados informados por el **propietario del sistema**. Las pruebas físicas fueron ejecutadas por el propietario sobre la Raspberry Pi real; **el agente de IA no accedió por SSH al equipo, no modificó su configuración activa y no reprodujo estas pruebas en hardware**.
- **Clasificación:** `CONFIRMED` = observado físicamente por el propietario; `IMPLEMENTED` = incorporado al repositorio; `REPORTED` = comunicación del propietario sin salida de comando adjunta.
- **Política de sanitización:** no se publican MAC, UUID privados, nombres personales de redes, contraseñas Wi-Fi/Samba/VNC ni otros identificadores innecesarios. La IP local de NOMAD y la dirección asignada al cliente Windows se conservan por ser relevantes para la validación.

---

## 1. Cronología de la instalación y configuración inicial

1. **`CONFIRMED` — Plataforma.** El sistema desplegado corresponde a Debian 13.6 sobre arquitectura ARM64 en Raspberry Pi 5, con NetworkManager 1.52.1.
2. **`CONFIRMED` — Primer intento de instalación.** La instalación falló al ejecutar:
   ```bash
   timeout 10s nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
   ```
   La causa exacta del fallo no quedó determinada. **No se afirma que fuera exclusivamente un problema del paginador.**
3. **`CONFIRMED` — Corrección aplicada por el propietario.** Tras sustituir la consulta por:
   ```bash
   PAGER=cat LC_ALL=C timeout 10s nmcli -f NAME,TYPE,DEVICE connection show
   ```
   la instalación se completó satisfactoriamente. Esta corrección quedó incorporada posteriormente a `install.sh` en el repositorio (`IMPLEMENTED`).
4. **`CONFIRMED` — Configuración local.** Se configuró el perfil HOME con su nombre exacto en `/etc/dorsett/network.env` y se dejó `MOBILE_PROFILE=""`. El perfil HOME fue reconocido correctamente por Dorsett.
5. **`CONFIRMED` — Perfil NOMAD.** Se creó `Dorsett-AP` con `connection.autoconnect=no`, banda 2.4 GHz, canal 6, WPA2 y dirección `10.42.0.1/24`.

---

## 2. Primera prueba de activación y DHCP

6. **`CONFIRMED` — Primer ensayo de activación del hotspot.** Se activó `Dorsett-AP` con protección de recuperación temporizada.
7. **`CONFIRMED` — Recuperación automática.** Transcurridos 300 segundos sin confirmación, se ejecutó la reversión automática y el sistema regresó a HOME.
8. **`CONFIRMED` — Servidor DHCP.** Se confirmó el inicio de `dnsmasq` para el modo `ipv4.method shared`.
9. **`CONFIRMED` — Rango y concesión.** Se observó el rango DHCP `10.42.0.10`–`10.42.0.254` y se concedió una dirección al Galaxy A10.
10. **`CONFIRMED` — Advertencia no bloqueante.** Se observó una advertencia `CAP_CHOWN` de `dnsmasq`. No impidió la concesión DHCP ni el funcionamiento del AP.

---

## 3. Ajuste WPS y servicios sobre NOMAD

11. **`CONFIRMED` — Solicitud de PIN observada.** Durante la primera prueba, Windows solicitó una entrada limitada a ocho dígitos, compatible con una solicitud de PIN WPS. No se presenta ese hecho como causa demostrada de todos los problemas iniciales.
12. **`CONFIRMED` — Desactivación de WPS.** El propietario ejecutó:
    ```bash
    sudo nmcli connection modify Dorsett-AP 802-11-wireless-security.wps-method 1
    ```
    Después de esta modificación se realizó una nueva prueba. El repositorio incorpora la propiedad para perfiles nuevos y existentes (`IMPLEMENTED`).
13. **`CONFIRMED` — Cliente Windows.** La PC Windows se conectó a `Dorsett-AP` y obtuvo IPv4 `10.42.0.212`.
14. **`CONFIRMED` — Conectividad local.** Desde Windows se enviaron cuatro paquetes `ping` a `10.42.0.1`: cuatro recibidos, `0 %` de pérdida y latencia promedio de `5 ms`.
15. **`CONFIRMED` — SSH.** La autenticación SSH mediante la red NOMAD fue exitosa.
16. **`CONFIRMED` — Puertos.** Los puertos TCP `5901` (VNC) y `445` (Samba) resultaron accesibles desde Windows en la red NOMAD.
17. **`CONFIRMED` — Samba.** El acceso al recurso compartido fue exitoso utilizando explícitamente el par de credenciales del **usuario Samba configurado en el sistema**: usuario `<USUARIO_SAMBA>` y su contraseña correspondiente. La contraseña se omite deliberadamente en este registro público.
18. **`CONFIRMED` — TightVNC.** Después de conectar la Tablet a `Dorsett-AP`, el acceso TightVNC fue exitoso.
19. **`REPORTED` / `CONFIRMED` — Causa de los problemas iniciales de VNC.** La Tablet permanecía conectada al router doméstico en lugar de `Dorsett-AP`; al conectarla al AP, el acceso VNC funcionó. No se atribuyó la incidencia a WPS ni a WayVNC.
20. **`CONFIRMED` — Regreso a HOME.** Tras la prueba controlada se confirmó el regreso a HOME.

---

## 4. Arranque autónomo y persistencia

21. **`CONFIRMED` — Fallback habilitado.** El servicio `dorsett-fallback.service` quedó habilitado para el arranque.
22. **`CONFIRMED` — Preparación del entorno aislado.** El propietario gestionó las redes Wi-Fi secundarias antes de la prueba aislada, de modo que no compitieran con `Dorsett-AP`.
23. **`CONFIRMED` — Arranque sin router.** Se realizó un arranque real sin router disponible.
24. **`CONFIRMED` — Activación automática.** `Dorsett-AP` se activó automáticamente al arrancar.
25. **`CONFIRMED` — Servicios en arranque autónomo.** Se accedió a VNC y Samba durante el arranque autónomo.
26. **`CONFIRMED` — Transferencia real.** Se transfirió un archivo desde la Raspberry Pi a la PC sin router disponible.
27. **`CONFIRMED` — Persistencia.** Al reaparecer la red doméstica, NOMAD permaneció operativo: no se produjo un retorno automático a HOME. Este comportamiento es intencional y evita cortar sesiones activas.

---

## 5. Conclusiones y límites de esta auditoría

- **`HOME`:** operativo y reconocido correctamente.
- **`NOMAD`:** operativo, incluido el arranque autónomo sin router.
- **`MOBILE`:** pendiente de configuración y validación; el Galaxy A10 participó como **cliente** de NOMAD, no como perfil móvil de Dorsett.
- **Recuperación temporizada:** comprobada físicamente en la prueba NOMAD de 300 segundos.
- **Regreso a HOME:** comprobado en pruebas anteriores; el alcance exacto de esta auditoría no cubre todas las variantes de la matriz `T01`–`T19`.
- **Regreso manual desde NOMAD después del arranque aislado:** pendiente de confirmación específica.
- **Recuperación dinámica ante caídas durante la ejecución:** no implementada en `v0.4.0`.
- **Interfaz gráfica de administración:** pendiente.

No se declaran aprobados todos los escenarios `T01`–`T19`. Los resultados simulados con *mocks* en la estación de desarrollo son validación de código, no evidencia de hardware.
