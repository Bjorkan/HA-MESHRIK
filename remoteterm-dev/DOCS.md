# MESHRIK - Bleeding Edge

This experimental Home Assistant app follows successful builds of the MESHRIK `main` branch through `ghcr.io/bjorkan/meshrik:edge`.

> **Warning:** Bleeding Edge may be unstable or broken. Use the stable **MESHRIK** app for normal operation and back up app data before testing updates.

MESHRIK is a fork of [RemoteTerm for MeshCore](https://github.com/jkingsman/Remote-Terminal-for-MeshCore). The source is maintained at [Bjorkan/MESHRIK](https://github.com/Bjorkan/MESHRIK).

Configuration, MQTT bootstrap, ingress, radio connection methods, and security guidance match the stable app. MQTT bootstrap honors the Supervisor broker's TLS setting and preserves an existing `mqtt_ha` fanout; update that fanout in the MESHRIK UI, or delete it and restart, when Supervisor broker credentials or settings change. This app uses the `meshrik-dev` slug and therefore has storage separate from the stable app. A legacy `remoteterm-dev` installation is a different app and its data is not migrated automatically.

Report wrapper issues in [HA-MESHRIK](https://github.com/Bjorkan/HA-MESHRIK/issues) and application issues in [MESHRIK](https://github.com/Bjorkan/MESHRIK/issues).
