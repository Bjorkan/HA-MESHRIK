# MESHRIK Home Assistant Smoke-Test Checklist

Run these tests on both `amd64` and `aarch64` (or suitable emulator)
before declaring either channel ready.

## Prerequisites

- Home Assistant with Supervisor
- At least one MESHRIK-compatible radio (serial, TCP, or BLE)
- Mosquitto broker add-on (optional, for MQTT discovery tests)

## 1. Repository and Installation

- [ ] Add repository `https://github.com/Bjorkan/HA-MESHRIK` in HA App Store
- [ ] Both **MESHRIK** and **MESHRIK - Bleeding Edge** appear in the store
- [ ] App names, descriptions, and icons are distinct and correct
- [ ] Stable installs successfully
- [ ] Bleeding Edge installs successfully
- [ ] Both can be installed side-by-side with separate entries in the sidebar
- [ ] Sidebar entries use distinct names: "MESHRIK" and "MESHRIK - Bleeding Edge"

## 2. Ingress and WebSocket

- [ ] Click sidebar entry → Ingress loads the MESHRIK UI
- [ ] WebSocket connects (StatusBar shows radio connection state)
- [ ] REST API calls succeed through ingress proxy
- [ ] No host port exposed unless explicitly configured in Network tab
- [ ] When host port 8000 is mapped, direct access works
- [ ] When host port is not mapped, direct port access is unavailable

## 3. Radio Connection

### Serial/USB

- [ ] Set `serial_port` to a valid device path → radio connects
- [ ] Leave `serial_port` empty → auto-detection runs
- [ ] Unplugged radio → StatusBar shows disconnected state
- [ ] Reconnect after unplug/replug

### TCP

- [ ] Set `tcp_host` and `tcp_port` → radio connects over TCP
- [ ] Invalid host/port → clear error, app continues serving UI

### BLE (best-effort, hardware-dependent)

- [ ] Set `ble_address` and `ble_pin` → BLE connection attempts

### No Radio

- [ ] Start without any radio → app serves UI, shows "not connected"
- [ ] Radio connection options can be reconfigured while running

## 4. Basic Auth

- [ ] Set `basic_auth_username` and `basic_auth_password`
- [ ] Restart → UI prompts for credentials
- [ ] Correct credentials → UI loads
- [ ] Incorrect credentials → 401, access denied
- [ ] Internal API calls (health, fanout) succeed with credentials
- [ ] Credentials with special characters (`"`, `\`, `$`, spaces) work
- [ ] Passwords do not appear in logs

## 5. MQTT Discovery and Bootstrap

### With Mosquitto

- [ ] Install Mosquitto broker add-on
- [ ] Start MESHRIK → `mqtt_ha` fanout is created automatically
- [ ] Home Assistant entities appear (see MESHRIK README_HA.md)
- [ ] MQTT TLS is honored when Mosquitto uses SSL
- [ ] Restart → existing `mqtt_ha` fanout is preserved, not overwritten
- [ ] Delete fanout in UI, restart → fanout is re-created from Supervisor data

### Without Mosquitto

- [ ] Start without Mosquitto → app starts, message about missing MQTT
- [ ] No crash or error loop

### Supervisor Token Absent

- [ ] Running outside Supervisor → token absent message logged
- [ ] App starts and functions normally

### MQTT Credential Changes

- [ ] Change Mosquitto broker credentials → existing fanout is preserved
- [ ] Update fanout manually in UI or delete+restart to pick up new settings

## 6. SQLite Persistence

- [ ] Database file exists at `/data/meshcore.db`
- [ ] Messages received before restart are visible after restart
- [ ] Contacts and channels persist across restarts
- [ ] App settings (blocked keys, favorites, etc.) persist
- [ ] App update: old data survives version upgrade
- [ ] WAL files are cleaned up on clean shutdown

## 7. Backup and Restore

- [ ] Create a Home Assistant backup that includes this app
- [ ] Restore the backup → database is intact
- [ ] Messages, contacts, channels all present after restore
- [ ] WAL consistency is maintained (no corruption after restore)
- [ ] Cold backup (app stopped, `/data` copied) produces a consistent snapshot

## 8. Side-by-Side Installation

- [ ] Install both stable and edge simultaneously
- [ ] Each has its own sidebar entry with distinct names
- [ ] Each has its own `/data/meshcore.db` (different slugs → separate storage)
- [ ] No data collision between channels
- [ ] Starting/stopping one does not affect the other
- [ ] Updating one does not affect the other

## 9. Renamed directories / wrapper packages

- [ ] Repo exposes `meshrik/` and `meshrik-dev/`; no remaining current directory named `remoteterm*`
- [ ] New GHCR packages `ghcr.io/bjorkan/ha-meshrik/meshrik-app*` exist for `amd64` and `arm64`
- [ ] First stable/edge reconciliation after rename rebuilds wrappers even when upstream digest is unchanged
- [ ] The new packages are published **before** relying on their names in Home Assistant
- [ ] Migration to new wrapper image names preserves each existing `meshrik`/`meshrik-dev` volume after backup
- [ ] Check that old `remoteterm-app*` images are not silently mistaken for the renamed packages
- [ ] The version and image in each manifest match the **new** wrapper's actual published tag/digest

## 9a. Legacy Slug Migration (if applicable)

- [ ] Existing `remoteterm` slug installation shows as separate app
- [ ] New `meshrik` slug installation does not overwrite legacy data
- [ ] Manual migration path is documented

## 10. Upgrade Behavior

- [ ] Stable update: new version installs without data loss
- [ ] Edge update: new version installs without data loss
- [ ] Rollback (install older version) preserves data
- [ ] Version number updates correctly in HA interface
- [ ] source-lock.json reflects the pinned digests

## 11. Shutdown and Signal Handling

- [ ] Stop app from HA → clean shutdown, no database corruption
- [ ] SIGTERM → uvicorn exits, serial device released
- [ ] No zombie processes after stop
- [ ] WAL checkpoint performed on shutdown

## 12. New startup policy and readiness

- [ ] Passive startup: only metadata/clock reads, no key export, radio writes, advertisement, drain or clear
- [ ] Sync startup: read contact/channel snapshots, no radio deletions, no RF advert, no offload
- [ ] Full without opt-ins: still no automatic radio writes or RF transmissions
- [ ] Legacy `skip_post_connect_sync=true` or `passive_startup=true` forces effective passive policy
- [ ] Lifecycle readiness (`initializing` vs `ready`/`degraded`) visible in `/api/health`
- [ ] Confirm app's MQTT bootstrap remains one-time and does not overwrite existing fanouts
- [ ] Stable and edge start with an empty `uv` cache and restricted network without downloading dev tools
- [ ] A synthetic HTTP bind delayed beyond 30 seconds but under the configured budget starts without a Supervisor restart
- [ ] A crashed process exits immediately with its status; a server that never binds stops at the configured timeout
- [ ] Readiness logs distinguish process exit, endpoint-not-bound, and unhealthy HTTP response
- [ ] SIGTERM and readiness timeout leave no Uvicorn child, port-8000 listener, radio owner, or MQTT helper
- [ ] Basic-authenticated readiness succeeds while the radio is unreachable and the UI reports disconnected/degraded
- [ ] Repeat the cold-start and shutdown checks on both `amd64` and `aarch64`

## 13. Release Channel Integrity

- [ ] Stable uses `ghcr.io/bjorkan/meshrik:latest` (pinned digest)
- [ ] Edge uses `ghcr.io/bjorkan/meshrik:edge` (pinned digest)
- [ ] Version tags match between config.yaml and source-lock.json
- [ ] Wrapper images are anonymously pullable from GHCR

## Results

| Test                  | amd64 | aarch64 | Notes |
| --------------------- | ----- | ------- | ----- |
| 1. Repository/Install |       |         |       |
| 2. Ingress/WebSocket  |       |         |       |
| 3. Radio Connection   |       |         |       |
| 4. Basic Auth         |       |         |       |
| 5. MQTT Discovery     |       |         |       |
| 6. SQLite Persistence |       |         |       |
| 7. Backup/Restore     |       |         |       |
| 8. Side-by-Side       |       |         |       |
| 9. Legacy Migration   |       |         |       |
| 10. Upgrade           |       |         |       |
| 11. Shutdown          |       |         |       |
| 12. Release Integrity |       |         |       |

## App-guideline compatibility review (October 2026)

Perform the following on both **amd64** and **aarch64**, for stable and Bleeding Edge:

1. On a fresh install, verify no host mapping for either `8000/tcp` or `5000/tcp`.
2. On an upgraded install, inspect and deliberately review **saved** network mappings;
   previous Virtual Companion mappings may still expose host port 5000.
3. In English and Swedish Configuration tabs, inspect all 27 labels/help descriptions.
   Check that private credentials are masked and destructive radio operations have clear
   warnings and default to `false`.
4. Confirm MQTT discovery succeeds with a broker **without** `hassio_api` permission,
   and that the app still starts when MQTT is absent.
5. Exercise serial auto-detection, optional BLE, and `/share` write access on real hardware.
6. Create/restore a **cold** Home Assistant backup and check SQLite integrity and data.
7. Test ingress assets, API, WebSockets, service worker, deep links and reloads in both
   Basic Auth configurations. **Known open issue:** root-absolute frontend URLs (wrapper
   #9; upstream MESHRIK #72) may escape the ingress prefix; manifest checks do not
   prove this works.
8. If enabling an external HTTP port, use Basic Auth and HTTPS. If enabling the Virtual
   Companion listener, limit its unauthenticated, non-TLS TCP port to the trusted LAN.
9. During passive/sync startup checks, do not perform any write or destructive radio
   operations; all maintenance toggles should remain disabled by default.

The static configuration checks in `tests/test-manifests.py` are automated. These steps
need a real Home Assistant Supervisor and are **not claimed as completed by CI**.
