#!/bin/sh
set -e

usage() {
    echo "Usage: $0 <path_to_nvidia_installer.run>"
    exit 1
}

[ "$(id -u)" -ne 0 ] && echo "Run as root." && exit 1
[ $# -eq 0 ] && usage
[ ! -f "$1" ] && echo "File not found: $1" && exit 1

cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

update-initramfs -u

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    make gcc linux-headers-$(uname -r) pkg-config xserver-xorg xorg-dev \
    libvulkan1 libglvnd-dev

chmod +x "$1"
