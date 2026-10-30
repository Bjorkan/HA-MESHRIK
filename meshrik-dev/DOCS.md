# MESHRIK - Bleeding Edge

This experimental Home Assistant app follows successful builds of the MESHRIK `main` branch through `ghcr.io/bjorkan/meshrik:edge`.

> **Warning:** Bleeding Edge may be unstable or broken. Use the stable **MESHRIK** app for normal operation and back up app data before testing updates.

MESHRIK is a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). The source is maintained at [Bjorkan/MESHRIK](https://github.com/Bjorkan/MESHRIK).

Configuration, MQTT bootstrap, ingress, radio connection methods, and security guidance match the stable app, including the `passive`/`sync`/`full` startup policies and individual opt-ins. `sync` is read-only with respect to the radio; `full` alone never authorizes writes, advertising or deletion. The `startup_clear_channel_slots` and `startup_allow_periodic_offload` options can remove device data and must remain off unless deliberately authorized. MQTT bootstrap honors the Supervisor broker's TLS setting and preserves an existing `mqtt_ha` fanout. A bounded background helper retries temporary Supervisor, broker-service, and MESHRIK API failures without delaying or restarting the radio process; missing MQTT remains optional. Update an existing fanout in the MESHRIK UI, or delete it and restart, when Supervisor broker credentials or settings change. This app uses the `meshrik-dev` slug and therefore has storage separate from the stable app. A legacy `remoteterm-dev` installation is a different app and its data is not migrated automatically.

Startup uses the preinstalled image environment and never runs `uv sync` or downloads development
tools. The wrapper gives the HTTP API a configurable 30–600-second monotonic startup budget (120
seconds by default), reports bounded readiness diagnostics, and terminates the application cleanly
after a crash or timeout. HTTP readiness does not wait for a radio connection: a disconnected radio
should leave the UI available with truthful radio status. Never reset the database, radio, channel
slots, or keys to repair HTTP startup.

The launcher's Home Assistant Supervisor token is used only for MQTT service discovery and is
removed from the MESHRIK child environment, so bots cannot retrieve it from `os.environ`. Bots
remain trusted code with MESHRIK's own radio, database, `/data`, and `/share` capabilities. Disable
bots and use Basic Auth behind HTTPS if port 8000 is exposed outside Home Assistant Ingress. See the
[Home Assistant app configuration](https://developers.home-assistant.io/docs/apps/configuration/)
for the distinction between default-role Supervisor API access and the separate Core API proxy.

Report wrapper issues in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues) and application issues in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).

## Home Assistant Ingress compatibility

The upstream MESHRIK frontend requires a base URL derived from the
`X-Ingress-Path` header sent by Home Assistant. Source-side changes are proposed
in [MESHRIK PR #270](https://github.com/Bjorkan/MESHRIK/pull/270);
this wrapper adds a **release-time image check** so a newly advertised MESHRIK
image must return correct Ingress-relative HTML and manifest URLs. The check
does not update currently installed stable/edge images. Only a newly published
upstream MESHRIK image built with the fix can enable the corrected behavior.

The browser must keep JS, CSS, API, WebSocket, and in-app navigation beneath
the active `/api/hassio_ingress/<session-token>/` prefix. MESHRIK's web-push/PWA
service worker is deliberately disabled **inside Home Assistant Ingress** to
avoid claiming the Home Assistant origin. Direct external access still needs
HTTPS and MESHRIK Basic Auth; Ingress does not secure exposed TCP ports.

See [Ingress test checklist](https://github.com/Bjorkan/HA-MESHRIK/blob/main/tests/INGRESS-TEST.md)
and [issue #9](https://github.com/Bjorkan/HA-MESHRIK/issues/9). Real
Home Assistant Supervisor verification is still required for both architectures
and both app channels.
