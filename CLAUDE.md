# Sistema de seguridad hogareño — Frigate + Tapo

Respondé siempre en español (Argentina).

## Objetivo

Seguridad de la casa para cuando no hay nadie: cámaras con detección de personas por IA,
alertas al celular y, ante intrusión confirmada, llamadas al dueño y a contactos de confianza.
**No** se llama automáticamente al 911: el dueño verifica el video y llama él (evita falsos
positivos; no hay API oficial). Todo corre local, sin nube de Tapo ni Tapo Care.

## Arquitectura

```
Tapo C320WS (RTSP)  →  Frigate (detección de personas, grabación)  →  MQTT (Mosquitto)
                                                                         ↓
                                                     Home Assistant (lógica, alertas, llamadas)
```

- Frigate 0.18, imagen `ghcr.io/blakeblackshear/frigate:stable`, en Docker Compose.
- Detector: OpenVINO en **CPU** (el servidor es AMD; OpenVINO GPU solo funciona con Intel),
  modelo YOLOv9-s 320x320 en ONNX (`config/model_cache/yolov9-s-320.onnx`, lo genera
  `build-model.sh`). Si la inferencia da alta, probar YOLOv9-t. ROCm descartado: la Vega del
  3500U no tiene soporte oficial.
- Decodificación de video por VAAPI con la Radeon Vega integrada (`LIBVA_DRIVER_NAME=radeonsi`).
- Mosquitto 2 con usuario/clave (`frigate` y `homeassistant`), sin puerto publicado:
  solo se accede por la red interna del compose.
- Home Assistant en contenedor (mismo compose, red bridge, puerto 8123). Llega a Frigate por
  `https://frigate:8971` con un usuario de Frigate propio, y a MQTT por `mosquitto:1883`.
- Puertos publicados en el servidor: 8971 (Frigate), 8555 (WebRTC) y 8123 (HA). El 8554
  (restream RTSP sin clave) y el 1883 (MQTT) solo se usan dentro de la red de Docker.

## Servidor

- `nzs@192.168.50.87` (Ubuntu 26.04, AMD Ryzen 5 3500U + Radeon Vega, 28 GB RAM, NVMe 935 GB
  compartido con Immich). Tailscale instalado: `100.83.112.106`.
- Proyecto en `/srv/apps/sistema-control-hogar` (misma convención que `/srv/apps/immich`);
  grabaciones en `/srv/apps/sistema-control-hogar/media`.
- El servidor está en `Etc/UTC` (no cambiarlo: lo comparten otros servicios). Frigate muestra
  la hora en la zona del navegador y HA tiene `TZ` propio; los logs y carpetas van en UTC.
- Clave admin de Frigate perdida → `auth.reset_admin_password: true` en `config.yml`,
  reiniciar, que el dueño la lea del log, y **quitar el flag** (si queda, cambia en cada reinicio).
- Acceso desde la PC de desarrollo con PuTTY:
  `plink -batch -i E:\Development\nzsitsolutions\keys\nzs-pk.ppk nzs@192.168.50.87 "<cmd>"`
  (copiar archivos con `pscp`). **No leer la clave ni datos ajenos al proyecto en el servidor**
  (hay otros servicios: Immich, control-nutricional); solo comandos sobre este proyecto.
- Desplegar: copiar los archivos cambiados con `pscp` a la misma ruta y luego
  `docker compose up -d` (o `restart <servicio>`). En Git Bash, `tar` necesita `--force-local`
  si la ruta tiene `C:`.

## Archivos

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Frigate + Mosquitto + Home Assistant. Pasa `/dev/dri/renderD128` para decodificar con la GPU AMD. |
| `.env` | Credenciales de Tapo (`FRIGATE_TAPO_USER/PASS`), `FRIGATE_MEDIA_PATH` y claves MQTT (`FRIGATE_MQTT_*`, `MQTT_HA_*`). **Secreto: nunca commitearlo ni mostrar su contenido.** |
| `.env.example` | Plantilla de `.env` con placeholders (sí se commitea). |
| `config/config.yml` | Config de Frigate: detector, go2rtc, objetos, grabación, cámara `patio`. |
| `mosquitto/mosquitto.conf` | Broker MQTT con `allow_anonymous false`. |
| `setup-mqtt.sh` | Genera `mosquitto/passwd` (ignorado) desde las claves MQTT de `.env`. |
| `homeassistant/configuration.yaml` | Config base de HA; carga `packages/`. El resto de `homeassistant/` es estado y está ignorado. |
| `homeassistant/packages/seguridad.yaml` | Modo `input_boolean.casa_vacia`, grupo `notify.dueno`, sensor "Frigate en línea" y automatizaciones de aviso. |
| `build-model.sh` | Exporta YOLOv9 a ONNX con el Dockerfile oficial de la doc de Frigate. |

## Cámara

- Tapo C320WS. Credenciales = "Cuenta de cámara" creada en la app Tapo
  (Configuración avanzada → Cuenta de cámara), **no** la cuenta TP-Link.
- IP `192.168.50.94` (nombre en la red: "IPC", MAC `c0:3a:55:c7:ae:a5`), reservada en el DHCP
  del router (ASUS RT-AX57, `192.168.50.1`). El servidor (`00:16:96:ee:51:ef`) también tiene
  reservada la `192.168.50.87`.
- `rtsp://USER:PASS@IP:554/stream1` → 2560x1440 H.264 15 fps + audio PCMA, rol `record`.
- `rtsp://USER:PASS@IP:554/stream2` → 640x360 H.264 15 fps + audio PCMA, rol `detect` (verificado).
- Tapo activa RTSP recién cuando existe la "Cuenta de cámara". El usuario **no** puede ser un mail.
- La cámara limita las conexiones simultáneas: con Frigate corriendo, no conectarse directo a
  `stream1` (la Tapo corta y go2rtc loguea ráfagas de `error=EOF`). Para probar, usar el
  restream: `rtsp://127.0.0.1:8554/patio` desde dentro del contenedor.
- Al mostrar logs o salidas de ffmpeg/go2rtc, enmascarar credenciales: `sed -E 's#//[^/ ]+@#//***@#g'`.
- Una vez estable, desactivar actualizaciones automáticas de firmware en la app Tapo
  (actualizaciones de Tapo rompieron RTSP alguna vez).

## Estado y próximos pasos

- [x] **1. Verificar hardware**: AMD Ryzen 5 3500U + Vega → OpenVINO CPU + VAAPI radeonsi.
- [x] **2. Completar `.env`**: credenciales Tapo, ruta de grabaciones y claves MQTT
      (`setup-mqtt.sh` corrido, auth verificada).
- [x] **3. IP de la cámara** en `config/config.yml`: `192.168.50.94`.
- [x] **4. Probar RTSP**: ambos streams OK; `detect` 640x360 coincide con la config.
- [x] **5. Generar el modelo**: `./build-model.sh` (28 MB, generado en el servidor).
- [x] **6. Levantar**: los 3 contenedores corren; Frigate valida la config y carga OpenVINO CPU.
      Clave admin de Frigate: la consulta el dueño con `docker logs frigate | grep -i password`
      (no leerla). UI en `https://192.168.50.87:8971`.
- [x] **7. Validar**: inferencia OpenVINO CPU ≈ 52 ms (≈55 % de capacidad con 1 cámara; para
      sumar cámaras evaluar YOLOv9-t), VAAPI activo (el 0 % de GPU en métricas es una limitación
      del monitor con AMD). Alertas `person` en Review con score 0.88–0.94, snapshot y clip.
      Prueba hecha con la cámara sobre el escritorio (todavía no está en su ubicación final).
- [ ] 8. Zonas y máscaras sobre la imagen real (excluir vereda, árboles, etc.).
- [ ] 9. Home Assistant (config y automatizaciones ya escritas; falta hacerlo en el servidor):
      1. ~~Onboarding en `http://192.168.50.87:8123`~~ ✔
      2. ~~Integración **MQTT**: broker `mosquitto`, puerto 1883, usuario `homeassistant` +
         `MQTT_HA_PASSWORD`~~ ✔ (sensor `binary_sensor.frigate_en_linea` creado).
         Si falla con "not authorised", es la clave mal pegada en el formulario.
      3. En Frigate (Settings → Users) crear el usuario `homeassistant` con rol `viewer`
         (si alguna función falla, probar con `admin`).
      4. HACS: `docker exec -it homeassistant bash -c "wget -O - https://get.hacs.xyz | bash -"`,
         reiniciar HA, agregar HACS desde la UI e instalar **Frigate**.
      5. Integración **Frigate**: URL `https://frigate:8971`, "Validate SSL" desactivado,
         modo "Frigate login" con el usuario del punto 3.
      6. ~~App HA en el celular~~ ✔ iPhone (iOS) → `notify.mobile_app_iphone` en el grupo `dueno`.
         Usuario HA: `faguirre`. Clave olvidada → `--script auth change_password` con HA frenado.
      7. Activar "Casa vacía", caminar frente a la cámara y verificar el aviso con foto.
- [ ] 10. Lógica de intrusión: persona detectada **y** sensor de apertura Zigbee → sirena + llamada
       al dueño y contactos (p. ej. Twilio). Modo "casa vacía" según presencia.
- [ ] 11. Más cámaras, UPS, internet de respaldo 4G, acceso remoto por Tailscale/WireGuard.

Ir tachando a medida que se completa cada paso.

## Reglas

- Antes de cambiar `config.yml`, validar el YAML; después de levantar, revisar `docker logs frigate`.
- Ante dudas de sintaxis, consultar https://docs.frigate.video (la config cambia entre versiones).
- No exponer puertos al router (nada de port forwarding); acceso remoto solo por VPN.
- No exponer el puerto 5000 de Frigate (sin autenticación); usar el 8971.
- No commitear `.env`, `config/model_cache/`, `mosquitto/passwd`, el estado de HA ni grabaciones.
- Después de cambiar `homeassistant/`, validar con
  `docker exec homeassistant python -m homeassistant --script check_config -c /config`.
