FROM rust:1.85-bookworm AS build

WORKDIR /build
COPY . /build

RUN cargo build --release --locked

FROM debian:bookworm-slim

ARG TINYPM_VERSION=unknown
ARG ABORA_VERSION=unknown
ARG IMAGE_SOURCE=https://github.com/AnimatedGTVR/Abora-OS

LABEL org.opencontainers.image.title="TinyPM" \
      org.opencontainers.image.description="TinyPM CLI container published from the Abora OS repository." \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.version="${TINYPM_VERSION}" \
      io.abora.version="${ABORA_VERSION}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /build/target/release/tinypm /usr/local/bin/tinypm
COPY --from=build /build/target/release/grab /usr/local/bin/grab

CMD ["tinypm", "--help"]
