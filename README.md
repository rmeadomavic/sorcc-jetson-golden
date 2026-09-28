# SORCC AI Kit: Jetson setup

Turns a Jetson Orin Nano Super (8 GB) into the offline AI kit used in the SORCC AI module:

- **Language**: a local chat model (Ollama, `qwen3:4b-instruct`)
- **Imagery**: image generation (ComfyUI with preset workflows)
- **Detection**: live camera object detection (Hydra)

Students reach all three from one launcher page. Only one tool runs at a time. After setup
the kit needs no internet and no accounts.

One script, `install.sh`, builds each kit from the internet. You do not need a finished
Jetson to copy from.

## What you need

- Jetson Orin Nano Super Developer Kit (8 GB)
- NVMe SSD, 256 GB or larger (a 128 GB+ microSD also works; NVMe is faster)
- **JetPack 7.2.1 or newer** (NVIDIA's current release). See step 1.
- USB webcam (Logitech C270 or similar), monitor, keyboard, mouse
- Internet on the Jetson, wired Ethernet if possible. Each kit downloads about 30 GB.

## Step 1: Check the JetPack version

Open a terminal on the Jetson and run:

```bash
lsb_release -rs; dpkg-query -W -f '${Version}\n' nvidia-l4t-core
```

You want `24.04` and `39.x`. Anything else: install JetPack 7.2.1 or newer with NVIDIA's USB
installer or SDK Manager (the Orin Nano **Super** configuration, so the GPU gets Super mode;
see [docs/jetpack7.md](docs/jetpack7.md#super-mode)).

## Step 2: Put this repo on the Jetson

```bash
sudo apt-get install -y git
git clone https://github.com/rmeadomavic/sorcc-jetson-golden.git
cd sorcc-jetson-golden
```

Optional, on the first kit only: `sudo ./scripts/jetpack7-test.sh` checks Super mode, GPU
math, a real ComfyUI render, and detection speed in about 30 minutes, and leaves its downloads
for the installer. The installer runs the GPU check on every kit anyway.

## Step 3: Run the installer

Log in to the desktop with the account students will use, then run:

```bash
sudo ./install.sh HYDRA-1
```

- `HYDRA-1` is this kit's name on the Detection dashboard. Use `HYDRA-2`, `HYDRA-3`, and so
  on for the other kits.
- It takes about 1 to 2 hours, mostly downloads. Leave it running.
- Every step prints what it is doing. If it stops, it says why and what to do. Fix that and
  run the same command again. Finished work is skipped, so re-running is quick.
- The full log is saved to `/var/log/sorcc-install.log`.

What it installs, in order: system packages; Chromium; Super power mode; Ollama and the
language model; Hydra, YOLO weights, and the class config; ComfyUI, 3 checkpoints, and 5 LoRAs;
then the launcher, services, wallpaper, and desktop shortcut. ComfyUI and Hydra run natively
from one pinned Python environment, and every download is checked against a pinned SHA-256.

## Step 4: Reboot and run the acceptance test

```bash
sudo reboot
```

After the reboot, plug in the USB camera and run:

```bash
sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
```

It exercises all three tools the way a student would. It takes about 5 minutes. A good
result is `PASS 24  WARN 1  FAIL 0`. The warning means the camera saw no person or object. Stand in
front of the camera and run it again to get `PASS 25`.

## Step 5: Check the desktop

1. The wallpaper is the SORCC AI KIT title on black.
2. Double-click **SORCC AI Kit** on the desktop. The first time, right-click it and choose
   **Allow Launching**.
3. Chromium opens the launcher. Launch each tool:
   - **Language**: ask a question and get an answer.
   - **Imagery**: the START HERE workflow opens. Select **Run** and wait for an image (about
     1 minute).
   - **Detection**: the camera image shows boxes around people and objects.
4. **Stop All** stops all three tools.

The full hand-off checklist is in [docs/acceptance-checklist.md](docs/acceptance-checklist.md).

## Step 6: Next kit

Repeat steps 1 to 5 on each Jetson with its own callsign. Each kit runs its own install and
keeps its own hostname, account, and keys. Never copy a disk from one Jetson to another.

## Rules

- The language model is `qwen3:4b-instruct` only. Never `llama3.2` (Meta's license prohibits
  military use). Never plain `qwen3:4b`, which is a "thinking" model that hangs instead of
  answering. The installer removes both if it finds them.
- One heavy tool at a time. 8 GB is not enough for two. The launcher enforces this.
- Keep ComfyUI images at 256 x 256. Bigger runs out of memory.
- Build every kit in a class on the same JetPack version, and do not change it during a course.
- Fallback only: if JetPack 7 ever fails on the GPU, the installer also supports JetPack 6.2.x
  in Docker ([docs/reflash-jetpack6-nvme.md](docs/reflash-jetpack6-nvme.md)).

## If something goes wrong

See [docs/troubleshooting.md](docs/troubleshooting.md). To send someone the logs, run
`sudo sorcc-diag` and share the `.tar.gz` file it creates.

## What is in this repo

| Path | What it is |
|---|---|
| `install.sh` | The installer. Start here. |
| `scripts/jetpack7-test.sh` | Optional first-kit check (step 2) |
| `jetpack7/` | The pinned Python packages (`requirements.lock`) |
| `comfyui/` | model list with checksums (`models.txt`), the three class workflows, and the `sorcc_student` helper that opens START HERE; `Dockerfile` and `requirements.lock` are the JetPack 6 fallback |
| `hydra/config.ini` | Hydra class config: observe-and-report only, everything else switched off |
| `scripts/sorcc_launcher.py` | The launcher page on port 8090, including the built-in chat page |
| `scripts/sorcc-jetson-smoke-test.sh` | Acceptance test |
| `scripts/sorcc-diag` | Collects logs for troubleshooting |
| `scripts/sorcc-lib.sh` | Helpers shared by the installer and the test |
| `scripts/refresh_workflow_copy.py` | Rewrites the student text inside the workflows |
| `assets/` | Wallpaper and two sample detection videos |
| `docs/` | JetPack 7 notes (Super mode, versions), JetPack 6 fallback, troubleshooting, acceptance checklist, class scope |
| `archive/` | Old build methods, kept for the record. Do not use. |

## What gets installed where

| Tool | Runs as | Port | Files |
|---|---|---|---|
| Launcher | `sorcc-launcher.service`, always on | 8090 | `/opt/sorcc/sorcc_launcher.py` |
| Language | `ollama.service`, on demand, CPU only | 11434 | Ollama 0.34.4, model in `/usr/share/ollama` |
| Imagery | `comfyui.service`, on demand | 8188 | `/opt/sorcc/comfyui/` (data), `/opt/sorcc/app/comfyui` (code) |
| Detection | `hydra-detect.service`, on demand | 8080 | `/opt/sorcc/hydra/` (config, weights), `/opt/sorcc/app/hydra` (code) |

ComfyUI and Hydra both run from the Python environment in `/opt/sorcc/venv`. Only the launcher
starts at boot. The launcher starts and stops the other three.
