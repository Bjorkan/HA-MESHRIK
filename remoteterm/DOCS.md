# MESHRIK

This Home Assistant app runs the stable channel of [MESHRIK](https://github.com/Bjorkan/MESHRIK), a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). It follows published stable MESHRIK releases through `ghcr.io/bjorkan/meshrik:latest`.

MESHRIK appears in the Home Assistant sidebar and is served through ingress. No host port is exposed unless you explicitly map `8000/tcp` on the Network tab.

> **Security:** MESHRIK is intended for trusted networks. Bots execute user-provided Python. If you expose the port directly, use HTTPS at a trusted reverse proxy, enable Basic Auth, and consider `disable_bots: true`.

## Radio connection

Configure exactly one connection method:

- **Serial/USB:** set `serial_port`, such as `/dev/ttyUSB0`, or leave it empty for auto-detection.
- **TCP:** set `tcp_host` and `tcp_port` (default `5000`).
- **BLE:** set `ble_address` and `ble_pin`. Containerized BLE is best effort; serial or TCP is recommended.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `serial_port` | auto | Serial device path; empty enables auto-detection. |
| `serial_baudrate` | `115200` | Serial baud rate. |
| `tcp_host` | none | Network radio host. |
| `tcp_port` | `5000` | Network radio port. |
| `ble_address` | none | BLE device address. |
| `ble_pin` | none | BLE PIN, required with `ble_address`. |
| `log_level` | `INFO` | `DEBUG`, `INFO`, `WARNING`, or `ERROR`. |
| `disable_bots` | `false` | Disable the Python bot system. |
| `basic_auth_username` | none | HTTP Basic Auth username. |
| `basic_auth_password` | none | HTTP Basic Auth password; set both credentials together. |
| `enable_message_poll_fallback` | `false` | Enable fallback message polling. |
| `force_channel_slot_reconfigure` | `false` | Force channel-slot reconfiguration on connect. |
| `skip_post_connect_sync` | `false` | Skip the post-connect radio sync. |

## MQTT and persistence

If the Supervisor exposes an MQTT service, the app creates a Home Assistant MQTT fanout on first start, including the broker's TLS setting. Internal setup requests use the configured Basic Auth credentials. User-edited fanout configuration is preserved on later starts.

If the Supervisor later changes the MQTT broker, credentials, port, or TLS setting, an existing `mqtt_ha` fanout is intentionally not overwritten. Update it in the MESHRIK UI, or delete it and restart the app to bootstrap it again from the current Supervisor service data.

The SQLite database is `/data/meshcore.db` and survives normal restart and app update operations. Keep Home Assistant backups of the app data before major upgrades.

This app uses the `meshrik` slug. A legacy installation using the `remoteterm` slug is a separate Home Assistant app and its `/data` directory is not migrated automatically.

## Updating and support

The wrapper receives a new app version only after the corresponding stable MESHRIK image has been published. Wrapper issues belong in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues); application issues belong in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).
