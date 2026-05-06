# MQTT Reference

GaScanner nodes send trunk-recorder events to the VPS over MQTT. The VPS broker is Mosquitto running directly on the host at `mqtt.georgiascanner.live:1883`.

## Broker

| Setting | Value |
|---------|-------|
| Host | `mqtt.georgiascanner.live` |
| Port | `1883` |
| TLS | Not used for node MQTT today |
| Auth | Required |
| Username convention | `tr_<county>` |

Containers on the VPS reach the broker with `tcp://host.docker.internal:1883`.

## Recommended Node Topics

The bootstrap script configures the trunk-recorder MQTT plugin with these defaults:

| Plugin field | Value | Notes |
|--------------|-------|-------|
| `topic` | `trunk_recorder/feeds` | Call lifecycle, recorder state, and rates |
| `unit_topic` | `trunk_recorder/units` | Unit on/off/call/join events |
| `message_topic` | omitted by default | Very high volume; add only when trunking messages are needed |
| `mqtt_audio` | `true` | Send call audio through MQTT |
| `mqtt_audio_type` | `wav` | Current bootstrap default |

tr-engine subscribes to `trunk_recorder/#`, so the feed and unit topics above are covered by a single wildcard.

## Consumers

| Consumer | Role |
|----------|------|
| ThinLine Radio | Scanner playback, call storage, user-facing radio UI |
| tr-engine | Analytics API, systems/sites/talkgroups/units, dashboard API |

Both consume from Mosquitto independently. A node does not send directly to either application container in the standard bootstrap path.

## Node Connectivity Test

From a node:

```bash
sudo apt-get install -y mosquitto-clients

mosquitto_pub -h mqtt.georgiascanner.live -p 1883 \
  -u "tr_COUNTY" -P "YOUR_PASSWORD" \
  -t "test/node" -m "hello"
```

From the VPS:

```bash
mosquitto_sub -h localhost -t 'trunk_recorder/#' -v
```

To wait for one call-end message:

```bash
mosquitto_sub -h localhost -t 'trunk_recorder/feeds/#' -C 1 -v
```

## Adding A Node MQTT User

On the VPS:

```bash
sudo mosquitto_passwd /etc/mosquitto/passwd tr_COUNTY
sudo systemctl reload mosquitto
```

Use one user per node or per county so credentials can be rotated independently.

## Audio Mode Notes

The bootstrap uses MQTT audio (`mqtt_audio: true`, `mqtt_audio_type: wav`) because remote nodes usually cannot share a filesystem with the VPS.

For a same-host trunk-recorder deployment, tr-engine can also read files through `TR_AUDIO_DIR`; that mode is not the standard remote-node bootstrap.
