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
- Detector: OpenVINO sobre GPU Intel integrada, modelo YOLOv9-s 320x320 en ONNX
  (`config/model_cache/yolov9-s-320.onnx`, lo genera `build-model.sh`).
- Mosquitto 2 para publicar eventos a Home Assistant (todavía no instalado).

## Archivos

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Frigate + Mosquitto. Pasa `/dev/dri/renderD128` para la GPU Intel. |
| `.env` | Credenciales de la "Cuenta de cámara" de Tapo (`FRIGATE_TAPO_USER/PASS`) y `FRIGATE_MEDIA_PATH`. **Secreto: nunca commitearlo ni mostrar su contenido.** |
| `config/config.yml` | Config de Frigate: detector, go2rtc, objetos, grabación, cámara `patio`. |
| `mosquitto/mosquitto.conf` | Broker MQTT. Hoy `allow_anonymous true`; pasar a usuario/clave al sumar HA. |
| `build-model.sh` | Exporta YOLOv9 a ONNX con el Dockerfile oficial de la doc de Frigate. |

## Cámara

- Tapo C320WS. Credenciales = "Cuenta de cámara" creada en la app Tapo
  (Configuración avanzada → Cuenta de cámara), **no** la cuenta TP-Link.
- `rtsp://USER:PASS@IP:554/stream1` → 2K, rol `record`.
- `rtsp://USER:PASS@IP:554/stream2` → baja resolución, rol `detect` (se asume 640x360; verificar).
- La IP en `config.yml` es un placeholder: `192.168.1.50` (aparece 2 veces en `go2rtc.streams`).
- Una vez estable, desactivar actualizaciones automáticas de firmware en la app Tapo
  (actualizaciones de Tapo rompieron RTSP alguna vez).

## Estado y próximos pasos

- [ ] **1. Verificar hardware**: `ls /dev/dri` y `lspci | grep -iE 'vga|3d'`.
      - Intel → config tal cual.
      - Sin GPU Intel → `device: CPU` en `detectors.ov`, borrar `ffmpeg.hwaccel_args`,
        comentar `devices` en el compose.
      - Nvidia → imagen `:stable-tensorrt` y detector `onnx`. AMD → `:stable-rocm` y `onnx`.
- [ ] **2. Completar `.env`** con las credenciales reales y la ruta del disco de grabaciones
      (verificar que exista, esté montada y tenga espacio: `df -h`).
- [ ] **3. Reemplazar la IP** de la cámara en `config/config.yml`.
- [ ] **4. Probar RTSP** antes de levantar nada:
      `ffprobe -rtsp_transport tcp "rtsp://USER:PASS@IP:554/stream2"` y ajustar
      `detect.width/height` a la resolución real.
- [ ] **5. Generar el modelo**: `./build-model.sh`.
- [ ] **6. Levantar**: `docker compose up -d`; clave admin con `docker logs frigate | grep -i password`;
      UI en `https://IP_SERVIDOR:8971`.
- [ ] **7. Validar**: inferencia razonable en System → Metrics; caminar frente a la cámara y ver
      alerta `person` en Review.
- [ ] 8. Zonas y máscaras sobre la imagen real (excluir vereda, árboles, etc.).
- [ ] 9. Home Assistant + integración Frigate (MQTT) + notificaciones con snapshot (Telegram o app HA).
- [ ] 10. Lógica de intrusión: persona detectada **y** sensor de apertura Zigbee → sirena + llamada
       al dueño y contactos (p. ej. Twilio). Modo "casa vacía" según presencia.
- [ ] 11. Más cámaras, UPS, internet de respaldo 4G, acceso remoto por Tailscale/WireGuard.

Ir tachando a medida que se completa cada paso.

## Reglas

- Antes de cambiar `config.yml`, validar el YAML; después de levantar, revisar `docker logs frigate`.
- Ante dudas de sintaxis, consultar https://docs.frigate.video (la config cambia entre versiones).
- No exponer puertos al router (nada de port forwarding); acceso remoto solo por VPN.
- No exponer el puerto 5000 de Frigate (sin autenticación); usar el 8971.
- No commitear `.env`, `config/model_cache/` ni grabaciones.
