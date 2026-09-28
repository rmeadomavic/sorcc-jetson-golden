# SORCC Class 02-26 — Jetson Orin Nano Super

## After Cloning This SD Card

Boot the Jetson, log in as `sorcc` (password: `sorcc`), then run:

```bash
sudo bash /home/sorcc/student-setup.sh
```

The script will prompt for your team number (1-5) and configure:
- Hostname: `hydra-team-{N}`
- Static IP on CHIMERA WiFi: `192.168.0.{50+N}`
- Clone the Hydra repo and install dependencies
- Docker, Ollama (with llama3.2:1b), Tailscale, SSH, mDNS

The script is idempotent — safe to re-run if anything fails.

## After Setup

1. Authenticate Tailscale: `sudo tailscale up`
2. Configure Hydra hardware: `bash ~/Hydra/scripts/hydra-setup.sh`
   - Docker images are pre-built — this step configures MAVLink, camera, and SDR
3. Reboot to apply hostname: `sudo reboot`

The Jetson will be discoverable as `hydra-team-{N}.local`.
Dashboard: `http://hydra-team-{N}.local:8080`

## Pre-installed on This Image

- Docker + `hydra-detect:latest` image (ready to run)
- Ollama + `llama3.2:1b` model
- Tailscale (each team's choice — paste a reusable authkey when `student-setup.sh` prompts to auto-join on boot, or skip and `sudo tailscale up` manually)
- Claude Code (`cc` alias with dangerous permissions)
- Python deps for Hydra (Jetson-safe, bare-metal for dev/testing)
- `yolov8n.engine` — FP16 TensorRT engine pre-built for Orin Nano (`~150 QPS`)
- Hardening baseline applied by `jetson-hardening/apply-hardening.sh`:
  - WiFi powersave disabled (rtl8822ce stability)
  - Persistent journald with 200 MB cap
  - Docker live-restore + log rotation (50 MB × 3)
  - 4 GB swapfile supplementing zram
  - `unattended-upgrades` and apt daily timers masked
  - `btop`, `v4l-utils` installed
  - Udev rules for RTL-SDR and Pixhawk-class autopilots (`/dev/autopilot`, `/dev/rtl_sdr`)
  - `sorcc-diag` — one-shot diagnostics collector

## Troubleshooting

If a Jetson misbehaves, collect a diagnostics bundle:

```bash
sudo sorcc-diag
# outputs /tmp/sorcc-diag-<hostname>-<timestamp>.tar.gz
```

Attach the tarball when reporting an issue.
