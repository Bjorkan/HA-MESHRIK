# MESHRIK

This Home Assistant app runs the stable channel of [MESHRIK](https://github.com/Bjorkan/MESHRIK), a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). It follows published stable MESHRIK releases through `ghcr.io/bjorkan/meshrik:latest`.

MESHRIK appears in the Home Assistant sidebar and is served through ingress. **Neither
`8000/tcp` (optional external HTTP) nor `5000/tcp` (Virtual Companion TCP) is
mapped to a host port on new installations.** Only enable a port on the Network tab if
necessary. Saved mappings from older installations may persist after an update.

> **Security:** MESHRIK is intended for trusted networks. Bots execute user-provided Python. If you expose the port directly, use HTTPS at a trusted reverse proxy, enable Basic Auth, and consider `disable_bots: true`.

The Supervisor's `/services/mqtt` endpoint is accessible without additional
`hassio_api` permissions. The wrapper requests only `mqtt:want` discovery: it does
not request elevated Supervisor or Home Assistant Core API access. See the
[Supervisor API guide](https://contributors.home-assistant.io/apps/guides/communication/).
The launcher removes Supervisor token variables from the MESHRIK child process environment,
but this is **not** a security boundary against code running in the same container.

This separation does not sandbox bots from MESHRIK itself. An enabled bot remains trusted code with
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
| `http_startup_timeout_seconds`        | `120`    | Wait 30–600 s for the HTTP API during cold startup; independent of radio readiness.                           |

The app now schedules connection bootstrap/reconnect through one worker and exposes distinct
`connecting`, `initializing`, `ready`, `degraded`, and `failed` states. A healthy HTTP response is
not proof the radio finished initialization. `sync` is the safe default. In `full`, **no**
maintenance opt-in is enabled automatically. When switching modes, the deprecated
`skip_post_connect_sync` and `passive_startup` must both be false unless you want `passive`.

**Warning:** enabling channel clearing or periodic offload can remove device-resident content.
Back up your radio and MESHRIK data before switching them on; destructive actions must never
be used as part of passive startup smoke testing.

## Application startup and readiness

The wrapper starts Uvicorn with the Python environment installed in the image. It does not run
`uv sync` or download development/test packages during startup, so app startup does not depend on
package-index or `uv` cache availability.

The wrapper allows up to `http_startup_timeout_seconds` (120 seconds by default) for `/api/health`
to respond. It reports whether the process exited, the HTTP endpoint is not bound yet, or the
endpoint returned an unhealthy response. This budget covers slower cold imports on busy and ARM
hosts; a genuine crash still exits immediately, and a timeout stops and reaps the application
process before Supervisor restarts the app.

HTTP readiness is intentionally independent of radio readiness. An unreachable or disconnected
radio should leave the UI and API available while the health response reports its actual radio
state. Do not reset the database, radio, channel slots, or keys to troubleshoot HTTP startup.

## MQTT and persistence

If the Supervisor exposes an MQTT service, the app creates a Home Assistant MQTT fanout, including the broker's TLS setting. Internal setup requests use the configured Basic Auth credentials. Discovery and fanout requests are retried for a bounded period in a background helper, so a temporarily unavailable Supervisor, broker app, or MESHRIK API does not require an app restart. This helper never delays or restarts the radio process and stops cleanly with the app. Logs report retry progress and tell you when automatic setup has stopped. User-edited fanout configuration is always preserved.

If the Supervisor later changes the MQTT broker, credentials, port, or TLS setting, an existing `mqtt_ha` fanout is intentionally not overwritten. Update it in the MESHRIK UI, or delete it and restart the app to bootstrap it again from the current Supervisor service data. Missing MQTT remains an optional integration failure and does not make MESHRIK startup fail.

The SQLite database is `/data/meshcore.db` and survives normal restart and app update operations. Keep Home Assistant backups of the app data before major upgrades.

This app uses the `meshrik` slug. A legacy installation using the `remoteterm` slug is a separate Home Assistant app and its `/data` directory is not migrated automatically.

## Updating and support

The wrapper receives a new app version only after the corresponding stable MESHRIK image has been published. Wrapper issues belong in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues); application issues belong in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).

## Installation, network exposure and backups

1. In Home Assistant, open **Settings → Apps → App Store → Repositories** and add
   `https://github.com/Bjorkan/HA-MESHRIK`.
2. Install **MESHRIK**, configure one serial, TCP, or BLE radio connection, and start it.
3. Open **Open Web UI**. Check the app's Log tab if it fails to start.

Ingress is the preferred method for accessing the web interface. Mapping `8000/tcp`
to a host port bypasses Home Assistant authentication; if you enable that mapping,
set both MESHRIK Basic Auth credentials and use HTTPS at a trusted reverse proxy.
For the unauthenticated **Virtual Companion TCP** server, configure its listener in
MESHRIK under **Settings → Integrations → MeshCore App (Virtual TCP Companion)**;
then, only if required, map `5000/tcp` to a trusted LAN host port. Choose a different
host port if stable and Bleeding Edge are installed together. Port mapping does not
enable the integration. Do not expose Virtual Companion TCP to the internet.

Home Assistant uses **cold backups** of this app: it stops the app briefly to
back up the SQLite database consistently. The default Docker AppArmor profile and
protection mode remain enabled. Serial auto-detection requires `uart: true`, while
Bluetooth availability is host-dependent. The app does not request host networking,
Docker API access, or extra Supervisor privileges. Bots can write to `/share` and
access app data; run only trusted bots.

## Known limitations

- The upstream MESHRIK frontend currently uses root-absolute URLs for assets,
  API requests, the service worker and navigation, which may escape the Home Assistant
  ingress prefix. See [wrapper issue #9](https://github.com/Bjorkan/HA-MESHRIK/issues/9)
  and [upstream issue #72](https://github.com/Bjorkan/MESHRIK/issues/72). Fixing this
  requires upstream prefix-aware routing and live Supervisor verification.
- BLE support in containers varies by host. Prefer serial or TCP when it is unreliable.
- Basic Auth protects HTTP access, **not** unauthenticated Virtual Companion TCP.
- The stable and experimental channels use separate app storage and databases.

## License

This Home Assistant wrapper is distributed under the
[MIT license](https://github.com/Bjorkan/HA-MESHRIK/blob/main/LICENSE).
MESHRIK and its dependencies retain their respective upstream license terms.
