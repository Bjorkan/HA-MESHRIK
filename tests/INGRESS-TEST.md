# Home Assistant Ingress acceptance checklist

This test plan accompanies [MESHRIK upstream PR #270](https://github.com/Bjorkan/MESHRIK/pull/270)
and [HA-MESHRIK issue #9](https://github.com/Bjorkan/HA-MESHRIK/issues/9).

## Automated release gate

Both `build-publish.yml` channels invoke `tests/verify-ingress-image.sh` with the
**immutable upstream MESHRIK image digest**, before building and advertising a new
Home Assistant wrapper. The test starts the upstream container without connecting
to a real radio, waits for an HTTP health response, checks root and Ingress deep-link
HTML and the prefixed manifest. A failure prevents the wrapper's version from being
advanced; this is intentional until the upstream fix has been published.

The script cannot validate Supervisor WebSocket proxying or the frontend browser
runtime. Upstream MESHRIK CI separately tests those layers.

## Manual Home Assistant OS smoke test (required)

Perform on both **amd64** and **aarch64**, and eventually on both release
channels when a fixed upstream image is published:

1. Confirm the advertised wrapper digest was built from an upstream source image
   that contains the ingress fix. Pre-fix stable images will not be corrected
   merely by merging this wrapper PR.
2. Open the MESHRIK sidebar through **Home Assistant Ingress**. In browser
   Network tools, all JS/CSS/favicon/bootstrap HTTP requests must target
   `/api/hassio_ingress/<session-token>/...`, not origin-root `/api` or `/assets`.
3. Open `/settings/radio`, a channel route, and a contact route. Refresh a nested
   URL; use Back/Forward and verify Router navigation remains inside the Ingress path.
4. Disconnect/reconnect the browser's WebSocket: its upgrade request must use
   the Ingress prefix and survive normal reconnection.
5. Ingress should not register MESHRIK's service worker or push subscription on
   Home Assistant's origin. Review the Application panel and Web Push UI.
6. Test with app Basic Auth unset and set; do not expose `8000/tcp` as a public
   host port. HA session auth is distinct from any direct-port Basic Auth.
7. Confirm direct HTTP (on a **trusted test network** behind HTTPS and Basic Auth)
   still serves resources at `/`.
8. Confirm optional `5000/tcp` Virtual Companion is never accidentally
   internet-accessible; it has no authentication or TLS.

Never enable destructive `startup_clear_channel_slots` or
`startup_allow_periodic_offload` during this testing. Record browser Network
results and Home Assistant version for follow-up, since this is not a real
Supervisor integration test in CI.

## Release dependency

Merge upstream PR #270, publish a new upstream edge image, verify edge on a
real Home Assistant installation, then ship the stable fix in a corresponding
MESHRIK stable release. Normal wrapper publication follows these images; do
not invent or hand-edit their immutable digests.
