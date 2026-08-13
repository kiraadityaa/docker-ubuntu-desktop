# syntax=docker/dockerfile:1

FROM --platform=linux/amd64 debian:trixie-slim

ARG TARGETARCH=amd64
ARG VERSION_ARG="0.0"
ARG VERSION_QMP="0.0.6"
ARG VERSION_WSD="0.4.2"
ARG VERSION_UTK="1.3.0"
ARG VERSION_VNC="1.7.0"
ARG VERSION_MESA="1.0.0"
ARG VERSION_OVMF="2026.05-2"
ARG VERSION_PASST="2026_07_28"
ARG VERSION_SEABIOS="1.17.0-1"
ARG VERSION_QEMU="1:11.0.3+ds-2"
ARG DEBIAN_SNAPSHOT="20260809T204446Z"

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NOWARNINGS=yes
ENV DEBCONF_NONINTERACTIVE_SEEN=true

# ------------------------------------------------------------
# Copy application source
# No bind mount is used because Railway does not support it.
# ------------------------------------------------------------

COPY ./src /run/
COPY ./web /var/www/

RUN chmod -R a+rx /run /var/www \
    && mkdir -p /storage

# ------------------------------------------------------------
# Install base packages
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bc \
        jq \
        xxd \
        tini \
        wget \
        7zip \
        7zip-rar \
        curl \
        aria2 \
        fdisk \
        nginx \
        unzip \
        swtpm \
        procps \
        ipcalc \
        ethtool \
        python3 \
        python3-pip \
        iptables \
        iproute2 \
        dnsmasq \
        xorriso \
        xz-utils \
        apt-utils \
        net-tools \
        e2fsprogs \
        diffutils \
        util-linux \
        iputils-ping \
        genisoimage \
        inotify-tools \
        netcat-openbsd \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Mesa Intel
# ------------------------------------------------------------

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        wget -q --timeout=10 \
          "https://github.com/qemus/mesa-intel/releases/download/v${VERSION_MESA}/mesa-intel_${VERSION_MESA}_amd64.deb" \
          -O /tmp/mesa-intel.deb \
        && apt-get update \
        && apt-get install --no-install-recommends -y /tmp/mesa-intel.deb \
        && rm -f /tmp/mesa-intel.deb \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# ------------------------------------------------------------
# QEMU + OVMF from Debian snapshot
# ------------------------------------------------------------

RUN echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ sid main" \
      > /etc/apt/sources.list.d/qemu-snapshot.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y -t sid \
        "seabios=${VERSION_SEABIOS}" \
        "ovmf-generic=${VERSION_OVMF}" \
        "qemu-utils=${VERSION_QEMU}" \
        "qemu-system-x86=${VERSION_QEMU}" \
    && if [ "$TARGETARCH" = "amd64" ]; then \
        apt-get install --no-install-recommends -y -t sid \
          "qemu-system-modules-opengl=${VERSION_QEMU}"; \
    fi \
    && rm -f /etc/apt/sources.list.d/qemu-snapshot.list \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# QEMU QMP
# ------------------------------------------------------------

RUN pip3 install \
      --no-cache-dir \
      --break-system-packages \
      --root-user-action=ignore \
      "qemu.qmp==${VERSION_QMP}"

# ------------------------------------------------------------
# Passt
# ------------------------------------------------------------

RUN wget -q --timeout=10 \
      "https://github.com/qemus/passt/releases/download/v${VERSION_PASST}/passt_${VERSION_PASST}_${TARGETARCH}.deb" \
      -O /tmp/passt.deb \
    && dpkg -i /tmp/passt.deb \
    && rm -f /tmp/passt.deb

# ------------------------------------------------------------
# websocketd
# ------------------------------------------------------------

RUN wget -q --timeout=10 \
      "https://github.com/qemus/websocketd/releases/download/v${VERSION_WSD}/websocketd-${VERSION_WSD}_${TARGETARCH}.deb" \
      -O /tmp/websocketd.deb \
    && dpkg -i /tmp/websocketd.deb \
    && rm -f /tmp/websocketd.deb

# ------------------------------------------------------------
# noVNC
#
# novnc.sh exists in the repository:
# /web/conf/novnc.sh
# and was copied to:
# /var/www/conf/novnc.sh
# ------------------------------------------------------------

RUN test -f /var/www/conf/novnc.sh \
    && chmod +x /var/www/conf/novnc.sh \
    && /var/www/conf/novnc.sh "${VERSION_VNC}"

# ------------------------------------------------------------
# Optional configuration files
# ------------------------------------------------------------

RUN if [ -f /var/www/conf/defaults.json ]; then \
        cp /var/www/conf/defaults.json /usr/share/novnc/defaults.json; \
    fi \
    && if [ -f /var/www/conf/mandatory.json ]; then \
        cp /var/www/conf/mandatory.json /usr/share/novnc/mandatory.json; \
    fi

# ------------------------------------------------------------
# Nginx
#
# Do NOT COPY nginx.conf because that file does not exist
# in the repository.
# ------------------------------------------------------------

RUN rm -f /etc/nginx/sites-enabled/default \
          /etc/nginx/conf.d/default.conf \
    && cat > /etc/nginx/conf.d/railway.conf <<'NGINX'
server {
    listen 8006;
    listen [::]:8006;

    server_name _;

    root /var/www;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX

# ------------------------------------------------------------
# Boot logo
# ------------------------------------------------------------

RUN wget -q --timeout=10 \
      "https://github.com/qemus/boot-logo/releases/download/v${VERSION_UTK}/boot-logo_${TARGETARCH}.bin" \
      -O /run/boot-logo \
    && chmod 755 /run/boot-logo

# ------------------------------------------------------------
# Version
# ------------------------------------------------------------

RUN echo "${VERSION_ARG}" > /etc/version

# ------------------------------------------------------------
# Railway persistent storage
#
# DO NOT use Docker VOLUME.
# Create the directory only.
# Mount a Railway Volume at /storage.
# ------------------------------------------------------------

RUN mkdir -p /storage

EXPOSE 22
EXPOSE 5900
EXPOSE 8006

ENV BOOT="mint"
ENV CPU_CORES="8"
ENV RAM_SIZE="16G"
ENV DISK_SIZE="550G"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
