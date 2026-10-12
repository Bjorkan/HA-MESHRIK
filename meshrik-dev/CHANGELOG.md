# Changelog

## 2026.10.12.10

- Package MESHRIK edge commit [`be6b66300b09385716418362030415e40abdaf50`](https://github.com/Bjorkan/MESHRIK/commit/be6b66300b09385716418362030415e40abdaf50).
- Pin source image digest `sha256:dcd934895b17b6d584d9589677fb895666649860a4038ff0670ab65e0214e777`.

## 2026.10.11.9

- Package MESHRIK edge commit [`77e9770478e7a93561298469bcb9e0a59764f531`](https://github.com/Bjorkan/MESHRIK/commit/77e9770478e7a93561298469bcb9e0a59764f531).
- Pin source image digest `sha256:9e73ef0b4a1c4457589d60c38f5ecd56f384a74ce8b7aaf17165c4a0e2aeb7a4`.

## 2026.10.11.8

- Package MESHRIK edge commit [`0ea396207da02918c7a29f748636898a8d608f76`](https://github.com/Bjorkan/MESHRIK/commit/0ea396207da02918c7a29f748636898a8d608f76).
- Pin source image digest `sha256:24eb3c66b6706e533cbd9f256a2cc2d39774b75d2050c97d332ff0c059641bba`.

## 2026.10.11.7

- Package MESHRIK edge commit [`e3c883a668370eb604a8bed1d482fe49a368374c`](https://github.com/Bjorkan/MESHRIK/commit/e3c883a668370eb604a8bed1d482fe49a368374c).
- Pin source image digest `sha256:57937cd24d0a8f3103190e70acd5bffae4a955858925653956638420eeb3f08d`.

## 2026.10.10.6

- Package MESHRIK edge commit [`e3c883a668370eb604a8bed1d482fe49a368374c`](https://github.com/Bjorkan/MESHRIK/commit/e3c883a668370eb604a8bed1d482fe49a368374c).
- Pin source image digest `sha256:57937cd24d0a8f3103190e70acd5bffae4a955858925653956638420eeb3f08d`.

## 2026.10.10.5

- Package MESHRIK edge commit [`b81307e2fea588ab78dd85b940b3b6324e0a33e0`](https://github.com/Bjorkan/MESHRIK/commit/b81307e2fea588ab78dd85b940b3b6324e0a33e0).
- Pin source image digest `sha256:1f4db2ae310e524f975bfda0096fb14e29e84a9d64945326dbaa6542b95a8653`.

## 2026.10.09.3

- Package MESHRIK edge commit [`d08bb1113f08928e16585f9f0d5d84aeae6df2e4`](https://github.com/Bjorkan/MESHRIK/commit/d08bb1113f08928e16585f9f0d5d84aeae6df2e4).
- Pin source image digest `sha256:29bc32bdbf48148d246b20c86b799aa4a15119c7414e0d67588f3e6388f5be9c`.

## 2026.08.12.0

- Rename the experimental app to MESHRIK - Bleeding Edge.
- Rename its internal slug to `meshrik-dev`; legacy app data is not migrated automatically.
- Document that this channel follows successful MESHRIK `main` builds.
- Preserve attribution to RemoteTerm for MeshCore and the original Home Assistant package.
- Replace the legacy source clone/frontend rebuild with a thin wrapper around `ghcr.io/bjorkan/meshrik:edge`.
- Remove the obsolete local `MessageInput.tsx` override.
- Publish the multi-architecture HA wrapper at the lowercase, versioned `ghcr.io/bjorkan/ha-meshrik/remoteterm-app-dev` package with required HA image labels.
