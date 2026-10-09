# Changelog

## 2026.08.12.0

- Rename the experimental app to MESHRIK - Bleeding Edge.
- Rename its internal slug to `meshrik-dev`; legacy app data is not migrated automatically.
- Document that this channel follows successful MESHRIK `main` builds.
- Preserve attribution to RemoteTerm for MeshCore and the original Home Assistant package.
- Replace the legacy source clone/frontend rebuild with a thin wrapper around `ghcr.io/bjorkan/meshrik:edge`.
- Remove the obsolete local `MessageInput.tsx` override.
- Publish the multi-architecture HA wrapper at the lowercase, versioned `ghcr.io/bjorkan/ha-meshrik/remoteterm-app-dev` package with required HA image labels.
