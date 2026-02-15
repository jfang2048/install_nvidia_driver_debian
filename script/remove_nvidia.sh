#!/bin/sh
#
# NVIDIA Driver Complete Removal Utility
# Version: 2.0.0

set -e
set -u

SCRIPT_NAME=$(basename "$0")
TARGET_VERSION=""
FALLBACK_SEARCH_PATHS="/home /root"

usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [OPTIONS] [INSTALLER_PATH]
Completely purge NVIDIA drivers and related components

Examples:
  # Basic removal with auto-detection
  sudo ${SCRIPT_NAME}

  # Specify installer for direct uninstall
  sudo ${SCRIPT_NAME} /path/to/NVIDIA-Linux-x86_64-XXX.XX.XX.run

  # Show help
  sudo ${SCRIPT_NAME} --help

Options:
  INSTALLER_PATH    Path to NVIDIA installer .run file
  -h, --help        Show this help message

Exit Codes:
1 - Root privileges required
2 - NVIDIA driver not detected
3 - Installer version mismatch
4 - Invalid installer path
5 - Uninstall failure
EOF
}

die() {
    echo "ERROR: $1" >&2
    exit $2
}

validate_root() {
    [ "$(id -u)" -eq 0 ] || die "This script must be run as root. Use: sudo ${SCRIPT_NAME}" 1
}

get_nvidia_version() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        die "NVIDIA driver not detected (nvidia-smi not found)" 2
    fi
    
    TARGET_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1 | tr -d ' ')
    echo "Detected NVIDIA driver version: ${TARGET_VERSION}"
}

validate_installer() {
    local installer_path=$1
    [ -f "$installer_path" ] || die "Installer not found: $installer_path" 4

    local installer_version=$(basename "$installer_path" | sed -n 's/.*-$[0-9]\+\.[0-9]\+\.[0-9]\+$\.run/\1/p')
    [ "$installer_version" = "$TARGET_VERSION" ] || die "Installer version mismatch (File: ${installer_version} vs Detected: ${TARGET_VERSION})" 3
}

find_installers() {
    find ${FALLBACK_SEARCH_PATHS} -type f \
        -name "NVIDIA-Linux-*-${TARGET_VERSION}.run" 2>/dev/null | sort | uniq
}

run_uninstall() {

    # /usr/bin/nvidia-uninstall
    local installer_path=$1
    echo "Executing uninstaller: ${installer_path}"
    chmod +x "$installer_path"
    "$installer_path" --uninstall --silent || die "Uninstaller failed for: ${installer_path}" 5
}

purge_system() {
    echo "Removing system components..."
    systemctl stop nvidia-*.service 2>/dev/null || true
    apt-get --purge -y remove 'nvidia-*' '_nvidia_' 'libxnvctrl*' >/dev/null
    apt-get --purge -y autoremove >/dev/null
    rm -rf /lib/modprobe.d/nvidia-* \
           /etc/modprobe.d/nvidia-* \
           /usr/lib/modprobe.d/nvidia-*
    modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    depmod -a
}

main() {
    # Argument handling
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        '') ;;  # Default case
        *)
            if [ -f "$1" ]; then
                INSTALLER_PATH=$1
            else
                die "Invalid installer path: $1" 4
            fi
            ;;
    esac

    validate_root
    get_nvidia_version

    # Custom installer handling
    if [ -n "${INSTALLER_PATH:-}" ]; then
        validate_installer "$INSTALLER_PATH"
        run_uninstall "$INSTALLER_PATH"
    else
        # Auto-find installers
        INSTALLERS=$(find_installers)
        if [ -n "$INSTALLERS" ]; then
            echo "Found compatible installers:"
            echo "$INSTALLERS" | nl
            read -p "Enter selection number (1) or skip (n): " choice
            case "${choice:-1}" in
                n|N) echo "Skipping installer uninstall" ;;
                *)
                    SELECTED=$(echo "$INSTALLERS" | sed -n "${choice:-1}p")
                    [ -n "$SELECTED" ] && run_uninstall "$SELECTED"
                    ;;
            esac
        fi
    fi

    purge_system
    echo "Removal complete. System reboot recommended."
}

main "$@"
