# The release workflow overrides this with the immutable digest behind :latest.
# The default keeps local builds convenient while stable CI remains reproducible.
ARG MESHRIK_IMAGE=ghcr.io/bjorkan/meshrik:latest
FROM ${MESHRIK_IMAGE}

ARG MESHRIK_IMAGE
ARG BUILD_VERSION=dev
LABEL io.hass.version="${BUILD_VERSION}" \
      io.hass.type="app" \
      io.hass.arch="aarch64|amd64" \
      io.hass.name="MESHRIK" \
      io.hass.description="MESHRIK web interface for MeshCore radio networks" \
      io.hass.url="https://github.com/Bjorkan/HA-MESHRIK" \
      org.opencontainers.image.base.name="${MESHRIK_IMAGE}" \
      org.opencontainers.image.source="https://github.com/Bjorkan/HA-MESHRIK" \
      org.opencontainers.image.licenses="MIT"

# Home Assistant wrapper dependencies.
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq curl \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
