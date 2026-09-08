# Multi-arch NDISafe Desk server image (hbbs + hbbr).
#
# The hbbs/hbbr server binaries come from the official rustdesk-server
# release; this image only repackages them so the README can reference a
# server image this project publishes. The binaries are fully static, so the
# final image is scratch-based like the official rustdesk-server image.
# As there: run it as `calvin207/ndisafedesk hbbs` (or `hbbr`).

# syntax=docker/dockerfile:1.4

FROM docker.io/debian:bookworm-slim AS builder

ARG TARGETARCH
ARG RUSTDESK_SERVER_VERSION=1.1.16

RUN case "${TARGETARCH}" in \
      amd64) asset="amd64" ;; \
      arm64) asset="arm64v8" ;; \
      *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates unzip wget \
    && wget -q -O /tmp/rustdesk-server.zip "https://github.com/rustdesk/rustdesk-server/releases/download/${RUSTDESK_SERVER_VERSION}/rustdesk-server-linux-${asset}.zip" \
    && mkdir /tmp/server \
    && unzip -q /tmp/rustdesk-server.zip -d /tmp/server \
    && mkdir -p /out \
    && cp /tmp/server/${asset}/hbbs /tmp/server/${asset}/hbbr /out/ \
    && chmod +x /out/hbbs /out/hbbr

FROM scratch

ENV PATH=/usr/local/bin:/usr/bin:/bin

COPY --from=builder /out/hbbs /out/hbbr /usr/local/bin/

WORKDIR /root
VOLUME /root

# hbbs needs 21115 (TCP), 21116 (TCP/UDP), 21118 (TCP).
# hbbr needs 21117 (TCP), 21119 (TCP).
EXPOSE 21115 21116/tcp 21116/udp 21117 21118 21119

CMD ["hbbs"]