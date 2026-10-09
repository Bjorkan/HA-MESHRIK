# MESHRIK Home Assistant apps

This repository packages [MESHRIK](https://github.com/Bjorkan/MESHRIK) for Home Assistant. MESHRIK is a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore); the original project and the original Home Assistant packaging remain credited in the repository history and license.

## Installation

1. In Home Assistant, go to **Settings → Apps → App Store**.
2. Open the menu (⋮), choose **Repositories**, and add:

   ```text
   https://github.com/Bjorkan/HA-MESHRIK
   ```

3. Install either **MESHRIK** or **MESHRIK - Bleeding Edge**.
4. Configure one radio connection and start the app.

The apps use the internal slugs `meshrik` and `meshrik-dev`. These distinct identities give each channel its own persistent `/data` volume. Existing installations that used the legacy `remoteterm` slugs are treated as different apps and require an explicit data migration.

## Release channels

| App | Source channel | Intended use |
| --- | --- | --- |
| [MESHRIK](remoteterm/) | `ghcr.io/bjorkan/meshrik:latest`, updated only for published stable MESHRIK releases | Normal use |
| [MESHRIK - Bleeding Edge](remoteterm-dev/) | `ghcr.io/bjorkan/meshrik:edge`, updated after successful builds from `main` | Testing; may be unstable or broken |

Both entries can be installed side by side. Their slugs, wrapper images, versions, and storage are independent.

Wrapper images are published as lowercase, independent GHCR packages:

- `ghcr.io/bjorkan/ha-meshrik/remoteterm-app:<stable-version>`
- `ghcr.io/bjorkan/ha-meshrik/remoteterm-app-dev:<edge-version>`

Only immutable app-version tags are used. Home Assistant resolves the tag from each manifest's `version`; wrapper `latest` tags are intentionally not part of the release contract.

### Stable release automation

The stable workflow accepts a `meshrik-stable-published` repository dispatch only after MESHRIK has published its release container. MESHRIK's release workflow sends the release version, commit, image digest, and release URL when the `HA_MESHRIK_DISPATCH_TOKEN` Actions secret is configured in the source repository. A daily reconciliation run handles missed events by resolving GitHub's latest non-prerelease MESHRIK release.

Before building, the HA workflow requires the release tag, commit, `:latest` image, immutable version tag, and optional dispatch payload to agree. It builds from the exact source digest, verifies the wrapper anonymously for AMD64 and ARM64, and only then commits the new manifest version and `source-lock.json`. Duplicate events are no-ops; a failed build leaves the advertised version unchanged and can safely be retried.

### Bleeding Edge automation

Each successful MESHRIK `:edge` publication can send a `meshrik-edge-published` dispatch carrying its commit and image digest. A daily reconciliation schedule discovers a missed publication directly from the public image's OCI revision metadata. The workflow rejects stale or reordered commits, pins the exact digest, cancels superseded work, and advertises a new date/run-number version only after its wrapper is anonymously pullable for both supported architectures.

For immediate stable and edge dispatches, create a fine-grained token scoped only to `Bjorkan/HA-MESHRIK` with **Contents: write**, then store it as the `HA_MESHRIK_DISPATCH_TOKEN` Actions secret in `Bjorkan/MESHRIK`. GitHub documents that permission for the [repository dispatch endpoint](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event). The scheduled reconciliation paths remain the recovery mechanism for missing or failed dispatches.

## Radio connection

MESHRIK supports serial/USB, TCP, and BLE. TCP and serial are recommended in Home Assistant; BLE access from a container depends on the host and is best effort. Configure exactly one method. Leaving `serial_port` blank enables automatic serial detection.

## Home Assistant MQTT integration

When the Mosquitto broker app is available, the wrapper asks the Supervisor for its connection details and creates an `mqtt_ha` fanout on first start. Existing fanout settings are never overwritten. MESHRIK continues to work when Mosquitto is absent.

See [MESHRIK's Home Assistant documentation](https://github.com/Bjorkan/MESHRIK/blob/main/README_HA.md) for the entities it publishes.

## Persistence and shared storage

Each app stores SQLite data at `/data/meshcore.db`, which Home Assistant preserves across restarts and updates. Because the app slugs differ, stable and Bleeding Edge do not share a database.

Bots can write files under `/share`, the Home Assistant shared volume. For example, `/share/meshrik/my-bot.log` is available to other apps and automations with access to that volume.

## External access

Ingress provides authenticated sidebar access on port 8000 without exposing a host port. To use a reverse proxy, assign a host port to `8000/tcp` on the app's **Network** tab. Direct port exposure bypasses Home Assistant authentication, so enable MESHRIK Basic Auth and use HTTPS at the proxy.

## Support and attribution

Report wrapper installation, Supervisor, ingress, or update issues in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues). Report application, UI, radio, or messaging issues in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).

MESHRIK is derived from RemoteTerm for MeshCore. See the linked original project and [this repository's license](LICENSE) for attribution and licensing details. The initial Home Assistant package was created by bhaggs; the preserved Git history records that work.
