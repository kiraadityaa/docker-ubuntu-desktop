FROM qemux/qemu:latest

# qemux tetap membutuhkan directory storage,
# tetapi tidak perlu Docker VOLUME / Railway Volume.
RUN mkdir -p /storage

# Disable KVM.
# qemux akan menjalankan QEMU menggunakan software emulation (TCG).
ENV KVM="N"

ENV BOOT="mint"
ENV CPU_CORES="8"
ENV RAM_SIZE="16G"
ENV DISK_SIZE="550G"

EXPOSE 22
EXPOSE 5900
EXPOSE 8006
