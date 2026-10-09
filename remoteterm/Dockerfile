# The release workflow overrides this with the immutable digest behind :latest.
# The default keeps local builds convenient while stable CI remains reproducible.
ARG MESHRIK_IMAGE=ghcr.io/bjorkan/meshrik:latest
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
