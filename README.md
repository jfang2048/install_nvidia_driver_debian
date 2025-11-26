# NVIDIA Driver Installation Guide

### Before Installation

```bash
cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

update-initramfs -u
# Install compilation tools and Xorg dependencies
apt install -y make gcc linux-headers-$(uname -r) pkg-config xserver-xorg xorg-dev build-essential
# Install Vulkan and GLVND development libraries
apt install -y libvulkan1 libglvnd-dev
```

-----

### Installation Method 1 (Manual)

```bash
# First, download the corresponding driver from the official website.
# Replace <version> with your actual downloaded version number (e.g., 550.127.05).
# Install with root privileges.

chmod 777 NVIDIA-Linux-x86_64-<version>.run
./NVIDIA-Linux-x86_64-<version>.run
```

### Installation Method 2 (Repository)

```bash
# This method may install an older version.
# You can check the available version info first using: apt search nvidia-driver
apt install nvidia-driver
apt -f install
```

### Verify Installation

Use `nvidia-smi` to check the status. Sometimes you may need to wait a moment or reboot the system for changes to take effect.

-----

### Clean Uninstall (If Installation Fails)

```bash
systemctl stop nvidia-*.service

# This step is required if the previous driver was installed manually (Method 1).
# Replace <version> with the specific version you installed.
./NVIDIA-Linux-x86_64-<version>.run --uninstall

apt-get --purge remove nvidia*
apt-get --purge remove "_nvidia_" "libxnvctrl*"
apt-get purge nvidia-driver-*
rm -rf /lib/modprobe.d/nvidia-installer-*
rm -rf /etc/modprobe.d/nvidia-installer-*
rm -rf /usr/lib/modprobe.d/nvidia-installer-*
modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia
apt-get autoremove
depmod
```

#### References

1.  [https://docs.heavy.ai/installation-and-configuration/installation/installing-on-ubuntu/install-nvidia-drivers-and-vulkan-on-ubuntu](https://docs.heavy.ai/installation-and-configuration/installation/installing-on-ubuntu/install-nvidia-drivers-and-vulkan-on-ubuntu)


---

#### tips

> It’s usually not a good idea to use the NVIDIA driver directly on a GNU/Linux physical machine. Most of the time, I use it inside a VM instead. If you want to passthrough the GPU to a VM, please read my other Markdown document.



