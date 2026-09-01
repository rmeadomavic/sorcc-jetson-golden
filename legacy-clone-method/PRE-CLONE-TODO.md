# Pre-Clone TODO

Things still to decide/do on the golden image before running the wipe and
flashing student cards. The wipe script (`~/pre-clone-wipe.sh`) deliberately
does NOT touch these — revisit each, then run the wipe last.

---

## 1. Hudra design handoff

**Location:** `~/Downloads/Hudra/` (+ `~/Downloads/Hudra.zip`, 94 KB)

**What it is:** A design-alignment bundle (4 markdown docs + React/JSX mock
reference) meant to close the gap between an HTML/React pitch mock and the
real `rmeadomavic/Hydra` repo.

**Open question:** Is this work already reflected in the Hydra repo, or
does some of it still need to land?

**Quick read of current state:**
- `hydra_detect/web/static/css/variables.css` header says "SORCC Design
  System — Hydra Detect v2.0" — design tokens look applied.
- `ops.js` uses the `HydraOps` namespace the handoff describes.
- 3-page SPA (`base.html` + `ops.html` + `config.html` + `settings.html`
  via Jinja `{% include %}`) matches the handoff's architecture notes.
- The handoff's "aspirational" surfaces (cockpit-strip, servo-pan dial,
  SDR sniffer ticker) do NOT appear in the repo.

**Decision needed:** Archive the bundle off-device (Drive/Dropbox/etc.)
and delete from the image, or leave on the student image as reference?

---

## 2. Downloads/Bambu\*

**Location:** `~/Downloads/Bambu_Studio_*` (~373 MB across 3 files)

3D-printer slicer AppImages — not needed on student Jetsons. Delete
whenever. Not tied to the Hudra decision.

```bash
rm -f ~/Downloads/Bambu_Studio_* ~/Downloads/BambuStudio_*
```

---

## 3. jetson-orin-servo/ + demo-servo.sh

**Location:** `~/jetson-orin-servo/` (280 KB) + `~/demos/scripts/demo-servo.sh`

**Current state:** `demo-servo.sh` uses hardware PWM via `pwmchip2` and
requires `jetson-pwm-enable.service` to have run at boot. That service is
not installed on this image — verify before you rely on this demo:

```bash
systemctl status jetson-pwm-enable.service
ls /sys/class/pwm/
```

If the service isn't present, either:
- Install it (see `~/jetson-orin-servo/jetgpio-fix/` or `findings.md`), or
- Swap the demo body to bit-bang on Pin 33 (jitter is fine for hobby
  servos; that's what `jetson-orin-servo/servo_sweep.py` does).

Either way, decide before cloning so all 5 students get the same working
demo.

---

## 4. Run the wipe, then clone

Once 1–3 are decided:

```bash
# Preview:
DRY_RUN=1 sudo bash ~/pre-clone-wipe.sh

# For real:
sudo bash ~/pre-clone-wipe.sh

# Then:
sudo poweroff
```

Follow `~/CLONING.md` from step 2 onward on your workstation.

---

## Already done this session (2026-04-29)

- Expanded golden image rootfs from ~95 GiB to fill the 256 GB SD card
  (`mmcblk0p1` is now 233 GB, 35% used). Used `growpart /dev/mmcblk0 1`
  + `resize2fs /dev/mmcblk0p1`.
- Installed `cloud-guest-utils` (provides `growpart`) — now baked into
  the golden image, so student clones will inherit it. Useful if a
  student gets a larger-than-source SD card.
- **Side effect for cloning:** the raw `dd` image is now ~238 GB (was
  ~95 GiB). Gzip will still compress the unused space well, but plan
  on a larger `.img.gz` and consider PiShrink before flashing if
  target cards may be smaller than 256 GB.

## Already done previous session (2026-04-19)

- Dropped `dreamshaperXL_lightning.safetensors` (6.5 GB) — saved disk,
  simplified demo.
- Updated `comfyui/workflows/README.txt`: removed XL exercise, settings
  block, and the "SDXL LoRAs only work with XL" footnote.
- Updated `comfyui/download-models.sh`: removed XL download line.
- Wrote `~/pre-clone-wipe.sh` (idempotent, DRY_RUN=1 supported).
- Wrote `~/CLONING.md` (step-by-step dd clone procedure).
- Confirmed servo path: `python3 servo_sweep.py` acquires GPIO line 43
  cleanly and releases on SIGINT. (Hardware-PWM path in demo-servo.sh
  not yet verified on this image — see item 3.)
- Fixed WiFi disconnect loop (rtl8822ce powersave) — set `wifi.powersave
  = 2` in `default-wifi-powersave-on.conf`; added to student-setup.sh B.5.
- Added `/home/sorcc/jetson-hardening/` with drop-in config + idempotent
  `apply-hardening.sh`. Wired into student-setup.sh as section B.6.
  Bakes in: persistent journald with 200 MB cap, Docker live-restore
  + log rotation (50 MB × 3), 4 GB swapfile supplementing zram,
  `unattended-upgrades` + apt-daily timers masked, `btop` + `v4l-utils`,
  udev rules for RTL-SDR (`/dev/rtl_sdr`, plugdev non-root) and
  Pixhawk/CubePilot/Holybro/FTDI (`/dev/autopilot`), and
  `/usr/local/bin/sorcc-diag` one-shot diagnostics collector.
- Pre-built FP16 TensorRT engine at `~/Hydra/models/yolov8n.engine`
  (~150 QPS / 7 ms, 9 MB). `.engine` is gitignored in the Hydra repo
  but rides the SD image. Rebuild if JetPack TRT version changes.
- `tailscale-autojoin.service` installed + enabled. Each team pastes
  their own reusable authkey at `student-setup.sh` G.5 (or leaves
  blank for manual `sudo tailscale up`). No shared authkey baked in.
- `pre-clone-wipe.sh` now also removes `/etc/default/tailscale`
  defensively so any testing authkey doesn't ride the clone.
