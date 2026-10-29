# MESHRIK - Bleeding Edge

This experimental Home Assistant app follows successful builds of the MESHRIK `main` branch through `ghcr.io/bjorkan/meshrik:edge`.

> **Warning:** Bleeding Edge may be unstable or broken. Use the stable **MESHRIK** app for normal operation and back up app data before testing updates.

MESHRIK is a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). The source is maintained at [Bjorkan/MESHRIK](https://github.com/Bjorkan/MESHRIK).

## Installation and configuration

1. Add `https://github.com/Bjorkan/HA-MESHRIK` under
   **Settings → Apps → App Store → Repositories**.
2. Install **MESHRIK - Bleeding Edge**, configure one radio connection and start the app.
3. Open its Home Assistant sidebar entry and use its Log tab to troubleshoot.

Both `8000/tcp` (direct HTTP) and `5000/tcp` (Virtual Companion TCP) are off by default
for new host-port mappings. Existing saved assignments may persist. Home Assistant
ingress needs no external HTTP port. Direct HTTP access bypasses Home Assistant login
and requires Basic Auth with HTTPS. Virtual Companion TCP is unauthenticated and has
no TLS: enable it in MESHRIK's integration settings and map its port **only** to a
trusted LAN, never the internet.

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


Configuration, MQTT bootstrap, ingress, radio connection methods, and security guidance match the stable app, including the `passive`/`sync`/`full` startup policies and individual opt-ins. `sync` is read-only with respect to the radio; `full` alone never authorizes writes, advertising or deletion. The `startup_clear_channel_slots` and `startup_allow_periodic_offload` options can remove device data and must remain off unless deliberately authorized. MQTT bootstrap honors the Supervisor broker's TLS setting and preserves an existing `mqtt_ha` fanout. A bounded background helper retries temporary Supervisor, broker-service, and MESHRIK API failures without delaying or restarting the radio process; missing MQTT remains optional. Update an existing fanout in the MESHRIK UI, or delete it and restart, when Supervisor broker credentials or settings change. This app uses the `meshrik-dev` slug and therefore has storage separate from the stable app. A legacy `remoteterm-dev` installation is a different app and its data is not migrated automatically.

Startup uses the preinstalled image environment and never runs `uv sync` or downloads development
tools. The wrapper gives the HTTP API a configurable 30–600-second monotonic startup budget (120
seconds by default), reports bounded readiness diagnostics, and terminates the application cleanly
after a crash or timeout. HTTP readiness does not wait for a radio connection: a disconnected radio
should leave the UI available with truthful radio status. Never reset the database, radio, channel
slots, or keys to repair HTTP startup.

MQTT service discovery uses a basic Supervisor endpoint and does not require extra
`hassio_api` or Home Assistant Core API permissions. The launcher removes Supervisor
token variables from the MESHRIK child process environment, but this is **not**
a security boundary against bots executing inside the same container. Bots
remain trusted code with access to MESHRIK's radio, database, `/data`, and `/share`. Disable
bots and use Basic Auth behind HTTPS if port 8000 is exposed outside Home Assistant Ingress. See the
[Home Assistant app configuration](https://contributors.home-assistant.io/apps/reference/configuration/)
for the distinction between default-role Supervisor API access and the separate Core API proxy.

Report wrapper issues in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues) and application issues in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).

## Backup, limitations and license

Home Assistant takes **cold backups** of the app's SQLite database, stopping the app
briefly to avoid inconsistent database snapshots. Serial auto-detection needs
`uart: true`; Bluetooth support varies by hardware. The wrapper uses the default
AppArmor profile, keeps protection mode on, and does not request host networking.

The upstream frontend's root-absolute asset, API, service worker and router URLs
remain a [known ingress compatibility risk](https://github.com/Bjorkan/HA-MESHRIK/issues/9).
They require an upstream fix and real Supervisor testing. Basic Auth never protects
Virtual Companion TCP.

Report wrapper defects in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues)
and application defects in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).
The wrapper is under the repository's
[MIT license](https://github.com/Bjorkan/HA-MESHRIK/blob/main/LICENSE);
upstream dependencies retain their respective licenses.
