FROM qemux/qemu:latest

# qemux membutuhkan folder ini saat startup.
# Tidak menggunakan Docker VOLUME dan tidak membutuhkan Railway Volume.
RUN mkdir -p /storage

ENV BOOT="mint"
ENV CPU_CORES="8"
ENV RAM_SIZE="16G"
ENV DISK_SIZE="550G"

EXPOSE 22
EXPOSE 5900
EXPOSE 8006
