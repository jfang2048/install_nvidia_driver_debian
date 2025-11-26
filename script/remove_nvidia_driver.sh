#!/bin/bash

set -u # exit on undefined variables

SCRIPT_NAME=$(basename "$0")
TARGET_VERSION=""
# Limit search to avoid hanging on large network mounts
FALLBACK_SEARCH_PATHS="/home /root /opt" 

usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [OPTIONS] [INSTALLER_PATH]
Completely purge NVIDIA drivers and related components.

Examples:
  sudo ${SCRIPT_NAME}
  sudo ${SCRIPT_NAME} /path/to/NVIDIA-Linux-x86_64-XXX.XX.XX.run

Options:
  INSTALLER_PATH    Path to NVIDIA installer .run file
  -f, --force       Skip version detection and aggressively purge system
  -h, --help        Show this help message
EOF
}

log() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }

die() {
    err "$1"
    exit "${2:-1}"
}

validate_root() {
    [ "$(id -u)" -eq 0 ] || die "This script must be run as root." 1
}

stop_display_manager() {
    log "Stopping Display Manager to release GPU..."
    # Detect common display managers
    local dms="gdm gdm3 sddm lightdm lxdm kdm"
    for dm in $dms; do
        if systemctl is-active --quiet "$dm"; then
            log "Stopping $dm..."
            systemctl stop "$dm"
        fi
    done
    # Kill X server just in case
    killall -9 Xorg 2>/dev/null || true
}

get_nvidia_version() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        TARGET_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1 | tr -d ' ')
        log "Detected NVIDIA driver version via nvidia-smi: ${TARGET_VERSION}"
    elif [ -f /proc/driver/nvidia/version ]; then
        TARGET_VERSION=$(grep "NVRM version:" /proc/driver/nvidia/version | awk '{print $8}')
        log "Detected NVIDIA driver version via /proc: ${TARGET_VERSION}"
    else
        warn "NVIDIA driver not running or detected."
        TARGET_VERSION=""
    fi
}

validate_installer() {
    local installer_path=$1
    [ -f "$installer_path" ] || die "Installer not found: $installer_path" 4

    # If we couldn't detect a version, we trust the user provided the right installer
    if [ -z "$TARGET_VERSION" ]; then
        return 0
    fi

    local installer_version
    installer_version=$(basename "$installer_path" | sed -n 's/.*-\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.run/\1/p')
    
    if [ "$installer_version" != "$TARGET_VERSION" ]; then
        warn "Installer version ($installer_version) does not match running driver ($TARGET_VERSION)."
        read -p "Proceed anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[yY] ]] || die "Aborted by user." 3
    fi
}

run_uninstall() {
    local installer_path=$1
    log "Executing uninstaller: ${installer_path}"
    chmod +x "$installer_path"
    "$installer_path" --uninstall --silent || warn "Uninstaller returned error, proceeding to manual purge."
}

purge_system() {
    log "Beginning system purge..."
    
    # 1. Stop NVIDIA services
    systemctl stop nvidia-persistenced nvidia-fabricmanager 2>/dev/null || true
    
    # 2. Package Manager Purge (Debian/Ubuntu specific)
    if command -v apt-get >/dev/null; then
        log "Purging apt packages..."
        apt-get purge -y '*nvidia*' 'libxnvctrl*' 'cuda*' 2>/dev/null
        apt-get autoremove -y 2>/dev/null
    else
        warn "Not a Debian-based system. Manual package removal required for RPM/Pacman systems."
    fi

    # 3. Clean DKMS
    if command -v dkms >/dev/null; then
        log "Cleaning DKMS modules..."
        dkms status | grep nvidia | cut -d, -f1,2 | tr -d ' ' | tr ',' '/' | while read -r module; do
            dkms remove "$module" --all 2>/dev/null || true
        done
    fi

    # 4. Remove Files
    log "Removing config files and blacklists..."
    rm -rf /lib/modprobe.d/nvidia-* \
           /etc/modprobe.d/nvidia-* \
           /usr/lib/modprobe.d/nvidia-* \
           /etc/X11/xorg.conf.d/nvidia* \
           /etc/X11/xorg.conf

    # 5. Unload Modules
    log "Unloading kernel modules..."
    modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    
    # 6. Update kernel dependencies
    log "Updating module dependencies..."
    depmod -a
    
    # 7. Update Initramfs (crucial for boot)
    if command -v update-initramfs >/dev/null; then
        log "Updating initramfs..."
        update-initramfs -u
    fi
}

main() {
    local FORCE_MODE=0
    local PROVIDED_INSTALLER=""

    # Argument parsing
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -f|--force) FORCE_MODE=1; shift ;;
            *)
                if [ -f "$1" ]; then
                    PROVIDED_INSTALLER=$1
                elif [[ "$1" == *.run ]]; then
                     die "Invalid installer path: $1" 4
                fi
                shift
                ;;
        esac
    done

    validate_root
    
    # Stop GUI first to ensure we can unload things
    stop_display_manager

    # Attempt detection
    get_nvidia_version

    # Logic: If we have an installer, use it. 
    # If we don't, but we detected a version, try to find one.
    # If we are in force mode, skip to purge.

    if [ -n "$PROVIDED_INSTALLER" ]; then
        validate_installer "$PROVIDED_INSTALLER"
        run_uninstall "$PROVIDED_INSTALLER"
    elif [ -n "$TARGET_VERSION" ] && [ $FORCE_MODE -eq 0 ]; then
        # Try to find installers
        # Check current directory first
        INSTALLERS=$(find . $FALLBACK_SEARCH_PATHS -maxdepth 4 -type f -name "NVIDIA-Linux-*-${TARGET_VERSION}.run" 2>/dev/null | head -n 5)
        
        if [ -n "$INSTALLERS" ]; then
            echo "Found potentially matching installers:"
            echo "$INSTALLERS" | nl
            read -p "Select installer number to run uninstall (or 's' to skip/purge only): " choice
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                SELECTED=$(echo "$INSTALLERS" | sed -n "${choice}p")
                [ -n "$SELECTED" ] && run_uninstall "$SELECTED"
            fi
        else
            log "No matching .run installers found. Proceeding to system purge."
        fi
    fi

    purge_system
    
    echo "-----------------------------------------------------"
    log "Removal complete." 
    echo "It is HIGHLY recommended to reboot immediately."
    read -p "Reboot now? (y/N): " rb
    if [[ "$rb" =~ ^[yY] ]]; then
        reboot
    fi
}

main "$@"
