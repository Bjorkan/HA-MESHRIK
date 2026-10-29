# MESHRIK (stable)

Run the stable [MESHRIK](https://github.com/Bjorkan/MESHRIK) web interface for MeshCore radios inside Home Assistant.

The app provides an authenticated Home Assistant sidebar via ingress and supports serial/USB, TCP or best-effort Bluetooth connections to a radio. MQTT discovery is optional. Choose **sync** for safe, read-only startup; destructive maintenance actions are off by default.

1. Add [this app repository](https://github.com/Bjorkan/HA-MESHRIK) in **Settings → Apps → App Store → Repositories**.
2. Install **MESHRIK** and configure one radio connection method.
3. Open the web interface from Home Assistant.

**Network security:** Neither the external HTTP port nor unauthenticated Virtual Companion TCP is mapped to the host by default. For a trusted LAN-only Virtual Companion client, enable the `5000/tcp` mapping under **Network**; never forward it to the internet. Direct HTTP access to `8000/tcp` bypasses Home Assistant authentication and requires separate Basic Auth and HTTPS.

Read the [full configuration and safety documentation](DOCS.md), [release history](CHANGELOG.md), and [support information](https://github.com/Bjorkan/HA-MESHRIK/issues).
