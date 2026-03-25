FROM ubuntu:24.04

ARG TINYPM_VERSION=unknown
ARG ABORA_VERSION=unknown
ARG IMAGE_SOURCE=https://github.com/AnimatedGTVR/abora-os

ENV DEBIAN_FRONTEND=noninteractive
ENV TINYPM_PREFIX=/opt/tinypm
ENV PATH=/opt/tinypm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.title="TinyPM V3" \
      org.opencontainers.image.description="TinyPM V3 CLI container published from the Abora OS repository." \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.version="${TINYPM_VERSION}" \
      io.abora.version="${ABORA_VERSION}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        findutils \
        gawk \
        grep \
        procps \
        sed \
        tar \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/tinypm
COPY . /tmp/tinypm

RUN /tmp/tinypm/scripts/install.sh --yes --native apt --flavor abora \
    && ln -s /opt/tinypm/bin/tinypm /usr/local/bin/tinypm \
    && ln -s /opt/tinypm/bin/tinypm /usr/local/bin/tiny \
    && ln -s /opt/tinypm/bin/tinypm /usr/local/bin/grab \
    && ln -s /opt/tinypm/bin/Parcel /usr/local/bin/Parcel \
    && ln -s /opt/tinypm/bin/syspm /usr/local/bin/syspm \
    && ln -s /opt/tinypm/bin/version /usr/local/bin/version \
    && rm -rf /tmp/tinypm

WORKDIR /root
CMD ["tinypm", "help"]
