FROM alpine:3.13
LABEL LABEL maintainer="Roman Posudnevskiy <roman.posudnevskiy@gmail.com>"

# Based on https://github.com/hashicorp/docker-consul

# This is the release of Nomad to pull in.
ARG NOMAD_VERSION=1.2.6
LABEL org.opencontainers.image.version=$NOMAD_VERSION

# This is the location of the releases.
ENV HASHICORP_RELEASES=https://releases.hashicorp.com

# Create a nomad user and group first so the IDs get set the same way, even as
# the rest of this may change over time.
RUN addgroup nomad && \
    adduser -S -G nomad nomad

# https://github.com/sgerrand/alpine-pkg-glibc/releases
ARG GLIBC_VERSION=2.33-r0

ADD https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub /etc/apk/keys/sgerrand.rsa.pub
ADD https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk \
    glibc.apk
RUN apk add --no-cache \
        glibc.apk \
 && rm glibc.apk

# Set up certificates, base tools, and Nomad.
# libc6-compat is needed to symlink the shared libraries for ARM builds
RUN set -eux && \
    apk add --no-cache ca-certificates curl dumb-init gnupg libcap openssl su-exec iputils jq iptables avahi-tools && \
    gpg --keyserver keyserver.ubuntu.com --recv-keys C874011F0AB405110D02105534365D9472D7468F && \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    apkArch="$(apk --print-arch)" && \
    case "${apkArch}" in \
        aarch64) nomadArch='arm64' \
                 apk add --no-cache libc6-compat ;; \
        armhf) nomadArch='arm' \
               apk add --no-cache libc6-compat ;; \
        x86) nomadArch='386' ;; \
        x86_64) nomadArch='amd64' ;; \
        *) echo >&2 "error: unsupported architecture: ${apkArch} (see ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/)" && exit 1 ;; \
    esac && \
    wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_${nomadArch}.zip && \
    wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS && \
    wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify nomad_${NOMAD_VERSION}_SHA256SUMS.sig nomad_${NOMAD_VERSION}_SHA256SUMS && \
    grep nomad_${NOMAD_VERSION}_linux_${nomadArch}.zip nomad_${NOMAD_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /tmp/build nomad_${NOMAD_VERSION}_linux_${nomadArch}.zip && \
    cp /tmp/build/nomad /bin/nomad && \
    if [ -f /tmp/build/EULA.txt ]; then mkdir -p /usr/share/doc/nomad; mv /tmp/build/EULA.txt /usr/share/doc/nomad/EULA.txt; fi && \
    if [ -f /tmp/build/TermsOfEvaluation.txt ]; then mkdir -p /usr/share/doc/nomad; mv /tmp/build/TermsOfEvaluation.txt /usr/share/doc/nomad/TermsOfEvaluation.txt; fi && \
    cd /tmp && \
    rm -rf /tmp/build && \
    gpgconf --kill all && \
    apk del gnupg openssl && \
    rm -rf /root/.gnupg && \
# tiny smoke test to ensure the binary we downloaded runs
    nomad version

# The /nomad/data dir is used by Nomad to store state. The agent will be started
# with /nomad/config as the configuration directory so you can add additional
# config files in that location.
RUN mkdir -p /nomad/data && \
    mkdir -p /nomad/config && \
    chown -R nomad:nomad /nomad

# set up nsswitch.conf for Go's "netgo" implementation which is used by Nomad,
# otherwise DNS supercedes the container's hosts file, which we don't want.
RUN test -e /etc/nsswitch.conf || echo 'hosts: files dns' > /etc/nsswitch.conf

# Expose the nomad data directory as a volume since there's mutable state in there.
VOLUME /nomad/data

# This is used for internal RPC communication between client agents and servers,
# and for inter-server traffic. TCP only.
EXPOSE 4647

# This is used by servers to gossip both over the LAN and WAN to other servers.
# It isn't required that Nomad clients can reach this address. TCP and UDP.
EXPOSE 4648 4648/udp

# This is used by clients and servers to serve the HTTP API. TCP only.
EXPOSE 4646

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# By default you'll get an insecure single-node development,
# exposes a web UI and HTTP endpoints, and bootstraps itself.
# Don't use this configuration for production.
CMD ["agent", "-dev", "0.0.0.0"]
