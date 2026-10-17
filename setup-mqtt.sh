#!/usr/bin/env bash
# Genera mosquitto/passwd con los usuarios de Frigate y Home Assistant
# tomando las claves de .env. Correrlo antes del primer `docker compose up`
# y cada vez que cambies una clave MQTT.
set -euo pipefail
cd "$(dirname "$0")"

set -a; source .env; set +a
: "${FRIGATE_MQTT_USER:?falta en .env}" "${FRIGATE_MQTT_PASSWORD:?falta en .env}"
: "${MQTT_HA_USER:?falta en .env}" "${MQTT_HA_PASSWORD:?falta en .env}"

# rm -rf: si se levantó el compose antes, Docker crea passwd como carpeta
docker run --rm --entrypoint sh -v "$PWD/mosquitto:/work" \
  -e U1="$FRIGATE_MQTT_USER" -e P1="$FRIGATE_MQTT_PASSWORD" \
  -e U2="$MQTT_HA_USER" -e P2="$MQTT_HA_PASSWORD" \
  eclipse-mosquitto:2 -c '
    umask 077 && touch /tmp/passwd &&
    mosquitto_passwd -b /tmp/passwd "$U1" "$P1" &&
    mosquitto_passwd -b /tmp/passwd "$U2" "$P2" &&
    rm -rf /work/passwd &&
    install -o 1883 -g 1883 -m 600 /tmp/passwd /work/passwd'

docker compose restart mosquitto 2>/dev/null || true
echo "mosquitto/passwd listo (usuarios: $FRIGATE_MQTT_USER, $MQTT_HA_USER)."
