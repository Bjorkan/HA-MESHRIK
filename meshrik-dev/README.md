# MESHRIK – Bleeding Edge

Experimental Home Assistant app tracking successfully published MESHRIK edge images. It can be unstable or broken. Use [MESHRIK stable](../meshrik/) for normal operation.

1. Add [this repository](https://github.com/Bjorkan/HA-MESHRIK) in **Settings → Apps → App Store → Repositories**.
2. Install **MESHRIK - Bleeding Edge**, choose one radio connection and open its Home Assistant sidebar entry.
3. Back up any important data before testing upgrades. This channel uses a separate database and app slug from stable.

**Safety:** The default **sync** startup reads radio information without writing radio configuration. Destructive maintenance flags remain off unless explicitly enabled. The optional Virtual Companion TCP port (`5000/tcp`) is disabled at the host by default; it has no authentication or TLS. Only enable it on a trusted LAN. External HTTP access also bypasses ingress authentication.

See [full configuration documentation](DOCS.md), [changelog](CHANGELOG.md), and [support issues](https://github.com/Bjorkan/HA-MESHRIK/issues).
