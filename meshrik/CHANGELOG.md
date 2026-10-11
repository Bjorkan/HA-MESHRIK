# Changelog

## 3.17.1.6

- Package [MESHRIK 3.17.1](https://github.com/Bjorkan/MESHRIK/releases/tag/v3.17.1) from commit `d08bb1113f08928e16585f9f0d5d84aeae6df2e4`.
- Pin source image digest `sha256:1a609379c6eeb2b6a53d027b933ff2d2754797a318683f6a16c9dc0b2bf2a353`.


## 3.17.1.3

- Package [MESHRIK 3.17.1](https://github.com/Bjorkan/MESHRIK/releases/tag/v3.17.1) from commit `d08bb1113f08928e16585f9f0d5d84aeae6df2e4`.
- Pin source image digest `sha256:1a609379c6eeb2b6a53d027b933ff2d2754797a318683f6a16c9dc0b2bf2a353`.


## 3.17.1

- Rename the Home Assistant app and internal slug to MESHRIK and `meshrik`.
- Note that legacy `remoteterm` app data requires explicit migration.
- Point user-facing documentation and support links to Bjorkan/MESHRIK and HA-MESHRIK.
- Preserve attribution to RemoteTerm for MeshCore and the original Home Assistant package.
- Wrap the stable `ghcr.io/bjorkan/meshrik:latest` image, with support for digest pinning in CI.
- Publish the multi-architecture HA wrapper at the lowercase, versioned `ghcr.io/bjorkan/ha-meshrik/remoteterm-app` package with required HA image labels.


## 3.16.2

- Track upstream RemoteTerm for MeshCore 3.16.2
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.16.0

- Track upstream RemoteTerm for MeshCore 3.16.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.15.2

- Track upstream RemoteTerm for MeshCore 3.15.2
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.15.0

- Track upstream RemoteTerm for MeshCore 3.15.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.14.1

- Track upstream RemoteTerm for MeshCore 3.14.1
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.14.0

- Track upstream RemoteTerm for MeshCore 3.14.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.13.0

- Track upstream RemoteTerm for MeshCore 3.13.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.12.3

- Track upstream RemoteTerm for MeshCore 3.12.3
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.12.2

- Track upstream RemoteTerm for MeshCore 3.12.2
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.12.1

- Track upstream RemoteTerm for MeshCore 3.12.1
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.12.0

- Track upstream RemoteTerm for MeshCore 3.12.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.11.3

- Track upstream RemoteTerm for MeshCore 3.11.3
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.11.1

- Track upstream RemoteTerm for MeshCore 3.11.1
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.11.0

- Track upstream RemoteTerm for MeshCore 3.11.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.9.0

- Track upstream RemoteTerm for MeshCore 3.9.0
- See upstream [CHANGELOG](https://github.com/jkingsman/Remote-Terminal-for-MeshCore/blob/main/CHANGELOG.md) for details


## 3.8.0

- Track upstream RemoteTerm for MeshCore 3.8.0 (2026-04-03)
- Per-channel hop width override
- Motion packet display on map
- Map dark mode
- Auto-resend for byte-perfect message transmission
- RSSI/SNR attachment to received packets
- Python 3.11+ now required (handled by upstream image)

## 1.0.0

- Initial Home Assistant app release
- Wraps upstream `docker.io/jkingsman/remoteterm-meshcore` image
- All `MESHCORE_*` environment variables configurable via app options
- SQLite database persisted to `/data/meshcore.db`
- Serial, TCP, and BLE connection modes supported
