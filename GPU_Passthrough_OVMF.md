# PCI Passthrough via OVMF Setup Guide

This guide details the hardware requirements, BIOS settings, kernel configurations, and scripts required to pass a GPU through to a virtual machine using KVM/QEMU and VFIO.

[**Reference: ArchWiki - PCI passthrough via OVMF**](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)

-----

### 1\. Hardware Requirements

Before proceeding, ensure your hardware meets the following criteria:

  * **CPU:** Must support Hardware Virtualization (VT-x/AMD-V) and IOMMU (VT-d/AMD-Vi).
  * **Motherboard:** Must support IOMMU configuration.
  * **GPU:** The GPU assigned to the guest VM must have a UEFI-capable ROM.

> **Important Hardware Note:** You should have a spare monitor or a monitor with multiple input ports connected to the different GPUs. The passthrough GPU will **not display anything** on the host once initialized. Using VNC or Spice will not improve graphical performance.

-----

### 2\. BIOS / UEFI Settings

Enter your BIOS setup and ensure the following features are enabled.

  * **Secure Boot:** [Enabled] (Note: Sometimes easier to disable during setup, but can be enabled).
  * **Fast Boot:** [Enabled]
  * **IOMMU:** [Enabled]
  * **Virtualization:**
      * **AMD:** SVM Mode [Enabled]
      * **Intel:** VT-d [Enabled]

-----

### 3\. Kernel Configuration

You need to enable IOMMU in your bootloader. Choose the method below that matches your bootloader (Systemd-boot or GRUB).

#### Option A: Systemd-boot (`/boot/loader/entries/arch.conf`)

If you are using `systemd-boot`, append the following to the `options` line:

```text
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTLABEL="PRIMARY" rootfstype=xfs add_efi_memmap intel_iommu=on iommu=pt rd.driver.pre=vfio-pci
```

*Note: Replace `intel_iommu=on` with `amd_iommu=on` if using an AMD CPU.*

#### Option B: GRUB (`/etc/default/grub`)

If you are using GRUB, edit the default command line options:

```bash
# Edit the configuration
vim /etc/default/grub

# Add the following parameters
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt rd.driver.pre=vfio-pci"
# Note: Use intel_iommu=on for Intel CPUs

# Update GRUB and reboot
update-grub
reboot
```

#### Verification

After rebooting, check if IOMMU is enabled:

```bash
dmesg | grep -e "DMAR" -e "IOMMU"
```

-----

### 4\. Verify IOMMU Groups

*An IOMMU group is the smallest unit of physical devices that can be passed through to a virtual machine.*

Use the following script to check if IOMMU is active and list how devices are grouped.

```bash
#!/bin/bash

# 1. Check if IOMMU is enabled
if ! dmesg | grep -e "DMAR" -e "IOMMU" | grep -q "enabled"; then
    echo "WARNING: IOMMU doesn't appear to be enabled!"
    echo "Check your BIOS settings and kernel parameters."
fi

# 2. Display all IOMMU groups and their devices
echo "Listing all IOMMU Groups:"
shopt -s nullglob
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s: ' "$n"
    lspci -nns "${d##*/}"
done
```

-----

### 5\. VFIO Driver Configuration

To ensure the host OS does not grab the GPU, you must blacklist the driver (e.g., Nouveau/Nvidia) and bind the device to `vfio-pci`.

#### A. Persistent Configuration (Recommended)

Add the PCI IDs of the devices you want to pass through (GPU and Audio controller) to the configuration files.

**File:** `/etc/modprobe.d/vfio.conf`

```bash
# Replace IDs with your specific device IDs (lspci -nn)
options vfio-pci ids=10de:2204,10de:1aef
```

**File:** `/etc/modprobe.d/blacklist-nouveau.conf`

```bash
blacklist nouveau
options nouveau modeset=0
```

#### B. Dynamic Binding Script

If you prefer to bind devices manually or via a script after boot (without rebooting), use the following script. This unbinds the current driver and attaches `vfio-pci`.

```bash
#!/bin/bash

# Target devices (Edit these IDs to match your specific hardware)
DEVICES="0000:09:00.1 0000:09:00.2 0000:09:00.3 0000:0a:00.1 0000:0a:00.2 0000:0a:00.3"

# 1. Unbind original driver and bind vfio-pci
for dev in $DEVICES; do
    # Unbind from current driver
    echo "$dev" | sudo tee /sys/bus/pci/devices/$dev/driver/unbind >/dev/null 2>&1
    
    # Override driver to vfio-pci
    echo "vfio-pci" | sudo tee /sys/bus/pci/devices/$dev/driver_override >/dev/null
    
    # Reprobe to attach vfio-pci
    echo "$dev" | sudo tee /sys/bus/pci/drivers_probe >/dev/null
done

# 2. Verify binding results
echo "Verifying driver status..."
for dev in $DEVICES; do
    echo -e "\nDevice: $dev"
    # Show the kernel driver currently in use
    lspci -ks ${dev#0000:} | grep "Kernel driver in use"
done
```


---


##### vgpu_unlock
https://krutavshah.github.io/GPU_Virtualization-Wiki/overview.html#system-requirements
https://github.com/DualCoder/vgpu_unlock


