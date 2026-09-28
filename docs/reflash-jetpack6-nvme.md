# Reflash a Jetson with JetPack 6.2.x on NVMe

This is the fallback path; the kit is built on JetPack 7. Use this only when the JetPack 7 test (`sudo ./scripts/jetpack7-test.sh`)
ends with **RECOMMENDATION: use the JetPack 6 backup**, or when a kit is on a JetPack version
the installer does not support (anything other than 7.2+ or 6.2.x).

## Why a kit might need JetPack 6

JetPack 7.2 (Jetson Linux r39, Ubuntu 24.04, CUDA 13) is what NVIDIA's download page offers
first, and the kit now installs on it natively (see [jetpack7.md](jetpack7.md)). JetPack 6.2.x
is the proven build from the 2026-07 class and stays as the fallback for when JetPack 7
fails on the GPU math, image, or detection checks.

Do not mix versions in one class: if the test sends you here, reflash every kit.

The JetPack 7 installer also updates the board's firmware (QSPI). A plain SD card image or
`apt` cannot go back to JetPack 6. Both methods below reflash the firmware and the NVMe
together, so they work from any starting point.

## What you need

- A PC running **Ubuntu 22.04 or 20.04** on x86-64. A native install works best; virtual
  machines often drop the USB connection during flashing.
- A USB-C **data** cable (some charge-only cables do not work)
- A jumper or a female-female jumper wire
- About 1 hour per Jetson
- **Take out any microSD card** from the Jetson so it cannot boot from that card afterward.

## Put the Jetson in recovery mode

1. Unplug the Jetson's power.
2. On the 12-pin button header under the module, connect the pins labeled **FC REC** and
   **GND** with the jumper.
3. Connect the USB-C port on the Jetson to the Ubuntu PC.
4. Plug the power back in. Nothing appears on the monitor in recovery mode; that is expected.
5. On the PC, run `lsusb`. You should see a line with `ID 0955:7523 NVIDIA Corp.`

## Option A: SDK Manager (easiest)

1. On the Ubuntu PC, download SDK Manager from <https://developer.nvidia.com/sdk-manager>
   (free NVIDIA developer account) and install it:
   `sudo apt install ./sdkmanager_*_amd64.deb`
2. Start `sdkmanager` and log in.
3. **Step 1:** Target Hardware **Jetson Orin Nano [8GB developer kit version]**.
   SDK Version **JetPack 6.2.2** (or the newest **6.2.x**). **Do not pick 7.x.**
4. **Step 2:** Keep Jetson Linux, Jetson Runtime Components, and Jetson SDK Components
   selected. Accept the licenses.
5. **Step 3 (flash dialog):**
   - Recovery mode setup: **Manual** (you already did it)
   - OEM configuration: **Pre-Config**, and enter the username and password the kit should
     have (the student account)
   - Storage device: **NVMe**
6. Select **Flash**. When it finishes, SDK Manager may ask for the Jetson's IP address to
   install the SDK components. Give it the address shown on the Jetson (connect Ethernet), or
   skip it; `install.sh` installs what the kit needs.
7. Unplug power, **remove the jumper**, and power on.

## Option B: Command line (no NVIDIA account)

On the Ubuntu PC:

```bash
mkdir ~/jp622 && cd ~/jp622
wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Jetson_Linux_r36.5.0_aarch64.tbz2
wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2

tar xf Jetson_Linux_r36.5.0_aarch64.tbz2
sudo tar xpf Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2 -C Linux_for_Tegra/rootfs/
cd Linux_for_Tegra/
sudo ./tools/l4t_flash_prerequisites.sh
sudo ./apply_binaries.sh
```

With the Jetson in recovery mode (see above), flash firmware and NVMe in one go. Keep the
`-super` board name; it enables Super mode:

```bash
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
  --showlogs --network usb0 --erase-all jetson-orin-nano-devkit-super internal
```

It ends with `Flash is successful`. Unplug power, **remove the jumper**, and power on. With a
monitor attached, finish the Ubuntu first-boot setup and create the student account. Then
connect to the internet and install the JetPack components:

```bash
sudo apt update
sudo apt install -y nvidia-jetpack
```

## Check the result

On the Jetson:

```bash
head -1 /etc/nv_tegra_release      # expect: # R36 (release), REVISION: 5.0 ...
lsb_release -rs                     # expect: 22.04
grep -o 'NAME=MAXN_SUPER' /etc/nvpmodel.conf   # expect: NAME=MAXN_SUPER (Super mode available)
findmnt -no SOURCE /                # expect: /dev/nvme0n1p1
```

Then go back to the [README](../README.md) and continue with step 2.
