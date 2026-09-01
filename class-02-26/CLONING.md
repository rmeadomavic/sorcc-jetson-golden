# Cloning the SORCC Jetson Golden Image

One-time procedure to take the master Jetson SD card and stamp out 5 student
clones (Teams 1–5).

---

## What you need

- The golden Jetson with its SD card installed
- A USB SD card reader on a Linux/Mac workstation
- 5 target SD cards (≥ the golden card's size — same model recommended)
- Roughly 30 min of hands-on time + ~30 min per flash

---

## Step 1 — Wipe the golden Jetson

On the golden Jetson:

```bash
# Preview what the script will do (no changes):
DRY_RUN=1 sudo bash /home/sorcc/pre-clone-wipe.sh

# Run for real:
sudo bash /home/sorcc/pre-clone-wipe.sh
```

When it finishes, shut down immediately:

```bash
sudo poweroff
```

**Do not log back in.** If you log in again, GNOME re-creates recently-used
files and dbus, the machine-id regenerates, etc. — you'd have to re-wipe.

---

## Step 2 — Pull the SD card and read it into an image

Power off the Jetson, pull the SD card, put it in a USB card reader on your
workstation. Identify which device it is:

```bash
lsblk
```

Look for a device that matches your card's size (e.g., `/dev/sdb` showing
~125 GB with `sdb1` and `sdb2` partitions). **Do not** pick `/dev/sda` —
that's your workstation's own disk.

Read the card to a compressed image file:

```bash
sudo dd if=/dev/sdX bs=4M status=progress conv=fsync | \
  gzip > hydra-golden-2026-04-19.img.gz
```

Replace `sdX` with your reader's device. Compression cuts a 64 GB card
image down to roughly 10–20 GB depending on fill. Takes 20–40 min.

---

## Step 3 — Flash each student card

Put a target SD card in the reader. Re-run `lsblk` to confirm which device
it is (the letter may change). Then:

```bash
gunzip -c hydra-golden-2026-04-19.img.gz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Repeat for all 5 cards. Each takes ~20 min.

**GUI alternative:** use [balenaEtcher](https://etcher.balena.io/) —
point it at the `.img.gz` file, point it at the target card, click Flash.

---

## Step 3.5 — (If target card is larger than source) grow the rootfs

The golden card is 256 GB with `mmcblk0p1` already expanded to ~233 GB.
If you flashed onto a card the same size or smaller (after PiShrink),
skip this. If you flashed onto a *larger* card and want the extra space:

```bash
sudo growpart /dev/mmcblk0 1
sudo resize2fs /dev/mmcblk0p1
```

`cloud-guest-utils` (which provides `growpart`) is pre-installed on the
golden image, so this works on every clone.

---

## Step 4 — First boot of each clone

Label each student card (Team 1, Team 2, …) so you can keep track.

For each cloned Jetson:

1. Insert the SD card, plug in keyboard, monitor, power
2. Boot (takes ~60 s the first time — regenerates SSH host keys +
   machine-id)
3. Log in:   user `sorcc`   password `sorcc`
4. Double-click the **SETUP THIS JETSON** icon on the desktop, or from a
   terminal:
   ```bash
   sudo bash /home/sorcc/student-setup.sh
   ```
5. When prompted, enter the team number (1–5). The script sets:
   - hostname → `hydra-team-N`
   - static IP on CHIMERA WiFi → `192.168.0.5N`
   - Enables SSH, mDNS, Hydra auto-start
6. After it completes, it chains into `~/Hydra/scripts/hydra-setup.sh`
   for the Hydra-specific config (MAVLink, camera, SDR)
7. Reboot:   `sudo reboot`

Each team will need to run `sudo tailscale up` themselves — Tailscale is
installed but deliberately not authenticated on the golden image.

---

## Verify a clone is healthy

On the cloned Jetson, from a terminal:

```bash
hostname                           # should be hydra-team-N
ip addr show wlP1p1s0 | grep inet  # should show 192.168.0.5N
systemctl is-active hydra-detect   # should be "active"
docker ps                          # should show hydra-detect container
```

Open a browser to `http://localhost:8080` — the Hydra dashboard should
load.

Run the servo demo to verify GPIO:
```bash
bash ~/demos/servo.sh
```

---

## If something goes wrong

**Flash fails with "No space left on device":** target card is smaller
than source. Use a same-capacity card, or shrink the image first with
[PiShrink](https://github.com/Drewsif/PiShrink).

**Cloned Jetson won't boot:** SD card wasn't flashed fully. `dd` reports
success even on bad cards — retry with a different card.

**Two clones got the same IP:** you picked the same team number twice,
or skipped the `student-setup.sh` step on one of them. Re-run the setup
script with the correct team number.

**Hydra dashboard won't load:** `sudo systemctl restart hydra-detect` and
wait 30 s. If still failing, `sudo journalctl -u hydra-detect -n 50`.
