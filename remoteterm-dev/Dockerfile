# The edge workflow overrides this with the immutable digest published for main.
ARG MESHRIK_IMAGE=ghcr.io/bjorkan/meshrik:edge
# hadolint ignore=DL3006
FROM ${MESHRIK_IMAGE}

ARG MESHRIK_IMAGE
ARG BUILD_VERSION=dev
LABEL io.hass.version="${BUILD_VERSION}" \
      io.hass.type="app" \
      io.hass.arch="aarch64|amd64" \
      io.hass.name="MESHRIK - Bleeding Edge" \
      io.hass.description="Experimental MESHRIK build tracking main" \
      io.hass.url="https://github.com/Bjorkan/HA-MESHRIK" \
      org.opencontainers.image.base.name="${MESHRIK_IMAGE}" \
      org.opencontainers.image.source="https://github.com/Bjorkan/HA-MESHRIK" \
      org.opencontainers.image.licenses="MIT"

# Home Assistant wrapper dependencies.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq curl \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
