# MESHRIK

This Home Assistant app runs the stable channel of [MESHRIK](https://github.com/Bjorkan/MESHRIK), a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). It follows published stable MESHRIK releases through `ghcr.io/bjorkan/meshrik:latest`.

MESHRIK appears in the Home Assistant sidebar and is served through ingress. No host port is exposed unless you explicitly map `8000/tcp` on the Network tab.

> **Security:** MESHRIK is intended for trusted networks. Bots execute user-provided Python. If you expose the port directly, use HTTPS at a trusted reverse proxy, enable Basic Auth, and consider `disable_bots: true`.

The wrapper enables Home Assistant's `hassio_api` only to discover the optional MQTT service.
Per the [official app configuration](https://developers.home-assistant.io/docs/apps/configuration/),
this grants Supervisor REST API access under the default `hassio_role`; it does not enable the
separate Home Assistant Core API proxy. The launcher sends the injected token only to the local
Supervisor service endpoint and removes Supervisor token variables from MESHRIK's child
environment. Bots therefore cannot read that bearer token from `os.environ`.

This isolation does not sandbox bots from MESHRIK itself. An enabled bot remains trusted code with
the application's database, radio operations, and writable `/data` and `/share` access. Disable
bots when operators who can create or edit them should not have those capabilities, especially
when exposing port 8000 outside Home Assistant Ingress.

## Radio connection

Configure exactly one connection method:

- **Serial/USB:** set `serial_port`, such as `/dev/ttyUSB0`, or leave it empty for auto-detection.
- **TCP:** set `tcp_host` and `tcp_port` (default `5000`).
- **BLE:** set `ble_address` and `ble_pin`. Containerized BLE is best effort; serial or TCP is recommended.

## Options

| Option                                | Default  | Description                                                                                                   |
| ------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------- |
| `serial_port`                         | auto     | Serial device path; empty enables auto-detection.                                                             |
| `serial_baudrate`                     | `115200` | Serial baud rate.                                                                                             |
| `tcp_host`                            | none     | Network radio host.                                                                                           |
| `tcp_port`                            | `5000`   | Network radio port.                                                                                           |
| `ble_address`                         | none     | BLE device address.                                                                                           |
| `ble_pin`                             | none     | BLE PIN, required with `ble_address`.                                                                         |
| `log_level`                           | `INFO`   | `DEBUG`, `INFO`, `WARNING`, or `ERROR`.                                                                       |
| `disable_bots`                        | `false`  | Disable the Python bot system.                                                                                |
| `basic_auth_username`                 | none     | HTTP Basic Auth username.                                                                                     |
| `basic_auth_password`                 | none     | HTTP Basic Auth password; set both credentials together.                                                      |
| `enable_message_poll_fallback`        | `false`  | Enable fallback message polling.                                                                              |
| `force_channel_slot_reconfigure`      | `false`  | Force channel-slot reconfiguration on connect.                                                                |
| `skip_post_connect_sync`              | `false`  | **Deprecated.** Forces `passive` regardless of `startup_policy`.                                              |
| `passive_startup`                     | `false`  | **Deprecated.** Also forces `passive` regardless of `startup_policy`.                                         |
| `startup_policy`                      | `sync`   | `passive` (read metadata), `sync` (read-only contact/channel snapshots) or `full` (only enabled maintenance). |
| `startup_export_private_key`          | `false`  | Full only: export sensitive private key material into app storage.                                            |
| `startup_sync_clock`                  | `false`  | Full only: write device clock.                                                                                |
| `startup_apply_flood_scope`           | `false`  | Full only: write configured flood scope.                                                                      |
| `startup_send_advertisement`          | `false`  | Full only: allow startup/periodic RF advertisements.                                                          |
| `startup_drain_messages`              | `false`  | Full only: drain pending device messages (potential offload).                                                 |
| `startup_reconcile_contacts`          | `false`  | Full only: application/contact maintenance.                                                                   |
| `startup_clear_channel_slots`         | `false`  | Full only: **destructive** device channel slot clearing.                                                      |
| `startup_allow_periodic_offload`      | `false`  | Full only: **destructive** recurring contact/channel offload.                                                 |
| `startup_enable_telemetry_collection` | `false`  | Full only: additional telemetry polling.                                                                      |
| `auto_reboot_on_clock_skew`           | `false`  | Explicit opt-in for a device reboot when clock repair requires it.                                            |
| `login_response_timeout_seconds`      | `5`      | Wait 1–60 s for an RF login response; independent of transport deadline.                                      |

The app now schedules connection bootstrap/reconnect through one worker and exposes distinct
`connecting`, `initializing`, `ready`, `degraded`, and `failed` states. A healthy HTTP response is
not proof the radio finished initialization. `sync` is the safe default. In `full`, **no**
maintenance opt-in is enabled automatically. When switching modes, the deprecated
`skip_post_connect_sync` and `passive_startup` must both be false unless you want `passive`.

**Warning:** enabling channel clearing or periodic offload can remove device-resident content.
Back up your radio and MESHRIK data before switching them on; destructive actions must never
be used as part of passive startup smoke testing.

## MQTT and persistence

If the Supervisor exposes an MQTT service, the app creates a Home Assistant MQTT fanout, including the broker's TLS setting. Internal setup requests use the configured Basic Auth credentials. Discovery and fanout requests are retried for a bounded period in a background helper, so a temporarily unavailable Supervisor, broker app, or MESHRIK API does not require an app restart. This helper never delays or restarts the radio process and stops cleanly with the app. Logs report retry progress and tell you when automatic setup has stopped. User-edited fanout configuration is always preserved.

If the Supervisor later changes the MQTT broker, credentials, port, or TLS setting, an existing `mqtt_ha` fanout is intentionally not overwritten. Update it in the MESHRIK UI, or delete it and restart the app to bootstrap it again from the current Supervisor service data. Missing MQTT remains an optional integration failure and does not make MESHRIK startup fail.

The SQLite database is `/data/meshcore.db` and survives normal restart and app update operations. Keep Home Assistant backups of the app data before major upgrades.

This app uses the `meshrik` slug. A legacy installation using the `remoteterm` slug is a separate Home Assistant app and its `/data` directory is not migrated automatically.

## Updating and support

The wrapper receives a new app version only after the corresponding stable MESHRIK image has been published. Wrapper issues belong in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues); application issues belong in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).
