# syntax=docker/dockerfile:1

FROM debian:trixie-slim

ARG TARGETARCH
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

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

# Copy the whole web directory.
# Railway does not support RUN --mount=type=bind.
COPY --chmod=755 ./web /var/www/

RUN <<EOF
  set -eu

  # ------------------------------------------------------------
  # Debian repositories
  # ------------------------------------------------------------
  echo "deb https://deb.debian.org/debian trixie non-free" \
    > /etc/apt/sources.list.d/non-free.list

  apt-get update

  # ------------------------------------------------------------
  # Base packages
  # ------------------------------------------------------------
  apt-get --no-install-recommends -y install \
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
    ca-certificates

  # ------------------------------------------------------------
  # Mesa Intel - amd64 only
  # ------------------------------------------------------------
  if [ "$TARGETARCH" = "amd64" ]; then
    wget \
      "https://github.com/qemus/mesa-intel/releases/download/v${VERSION_MESA}/mesa-intel_${VERSION_MESA}_amd64.deb" \
      -O /tmp/mesa-intel.deb \
      -q \
      --timeout=10

    apt-get --no-install-recommends -y install \
      /tmp/mesa-intel.deb
  fi

  # ------------------------------------------------------------
  # QEMU / OVMF from Debian snapshot
  # ------------------------------------------------------------
  echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ sid main" \
    > /etc/apt/sources.list.d/qemu-snapshot.list

  apt-get update

  apt-get --no-install-recommends -y -t sid install \
    "seabios=${VERSION_SEABIOS}" \
    "ovmf-generic=${VERSION_OVMF}" \
    "qemu-utils=${VERSION_QEMU}" \
    "qemu-system-x86=${VERSION_QEMU}"

  if [ "$TARGETARCH" = "amd64" ]; then
    apt-get --no-install-recommends -y -t sid install \
      "qemu-system-modules-opengl=${VERSION_QEMU}"
  fi

  # ------------------------------------------------------------
  # QEMU QMP
  # ------------------------------------------------------------
  pip3 install \
    --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    "qemu.qmp==${VERSION_QMP}"

  # ------------------------------------------------------------
  # Passt
  # ------------------------------------------------------------
  wget \
    "https://github.com/qemus/passt/releases/download/v${VERSION_PASST}/passt_${VERSION_PASST}_${TARGETARCH}.deb" \
    -O /tmp/passt.deb \
    -q \
    --timeout=10

  dpkg -i /tmp/passt.deb

  # ------------------------------------------------------------
  # websocketd
  # ------------------------------------------------------------
  wget \
    "https://github.com/qemus/websocketd/releases/download/v${VERSION_WSD}/websocketd-${VERSION_WSD}_${TARGETARCH}.deb" \
    -O /tmp/wsd.deb \
    -q \
    --timeout=10

  dpkg -i /tmp/wsd.deb

  # ------------------------------------------------------------
  # Install noVNC
  # ------------------------------------------------------------
  if [ -f /var/www/conf/novnc.sh ]; then
    chmod +x /var/www/conf/novnc.sh
    /var/www/conf/novnc.sh "$VERSION_VNC"
  else
    echo "ERROR: /var/www/conf/novnc.sh not found"
    exit 1
  fi

  # ------------------------------------------------------------
  # Optional noVNC configuration files
  # ------------------------------------------------------------
  if [ -f /var/www/conf/defaults.json ]; then
    cp /var/www/conf/defaults.json /usr/share/novnc/defaults.json
  fi

  if [ -f /var/www/conf/mandatory.json ]; then
    cp /var/www/conf/mandatory.json /usr/share/novnc/mandatory.json
  fi

  # ------------------------------------------------------------
  # Nginx configuration
  #
  # Railway does not have the original nginx.conf from the
  # repository, so create a minimal configuration here.
  # ------------------------------------------------------------
  rm -f /etc/nginx/sites-enabled/default
  rm -f /etc/nginx/conf.d/default.conf

  cat > /etc/nginx/conf.d/railway.conf <<'NGINX'
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
  # Version
  # ------------------------------------------------------------
  echo "$VERSION_ARG" > /etc/version

  # ------------------------------------------------------------
  # Cleanup
  # ------------------------------------------------------------
  rm -f /etc/apt/sources.list.d/qemu-snapshot.list

  apt-get clean

  rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*
EOF

# Application scripts
COPY --chmod=755 ./src /run/

# ------------------------------------------------------------
# Boot logo
# ------------------------------------------------------------
RUN wget \
    "https://github.com/qemus/boot-logo/releases/download/v${VERSION_UTK}/boot-logo_${TARGETARCH}.bin" \
    -O /run/boot-logo \
    -q \
    --timeout=10 \
  && chmod 755 /run/boot-logo

# Railway does not support Docker VOLUME.
# Create the directory; mount a Railway Volume to /storage.
RUN mkdir -p /storage

EXPOSE 22 5900 8006

ENV BOOT="mint"
ENV CPU_CORES="8"
ENV RAM_SIZE="16G"
ENV DISK_SIZE="550G"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
