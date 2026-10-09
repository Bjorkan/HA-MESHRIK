# The edge workflow overrides this with the immutable digest published for main.
ARG MESHRIK_IMAGE=ghcr.io/bjorkan/meshrik:edge
FROM ${MESHRIK_IMAGE}

ARG MESHRIK_IMAGE
LABEL org.opencontainers.image.base.name="${MESHRIK_IMAGE}"

# Home Assistant wrapper dependencies.
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq curl \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
