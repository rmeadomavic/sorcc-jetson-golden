# Jetson AI Kit Setup

Turns a Jetson Orin Nano Super (8 GB) into a self-contained offline AI box: LLM chat
(Ollama), image generation (ComfyUI), and live camera object detection (Hydra), all
behind one launcher web page, one tool at a time. No accounts, no cloud.

## You need

- Jetson Orin Nano Super dev kit with a 128 GB or larger microSD
- USB webcam (Logitech C270 or similar)
- The application payload: copy it over the LAN from an already-built Jetson, or from
  your artifact stash
- Internet access on the Jetson for the JetPack update

## Setup

1. Update to JetPack 6.2.2 / L4T 36.4.7 and bring both QSPI firmware slots to 36.4.7.
   Firmware is per-board; commands in runbook step 3.
2. Install the browser: `sudo snap install chromium`
3. Stage the payload at `~/sorcc-stage/` and load the two Docker images. Runbook
   step 5 lists the exact tree and image pins.
4. Copy `scripts/sorcc-target-finalize.sh` from this repo to the Jetson and run:

   ```bash
   sudo ./sorcc-target-finalize.sh "$(id -un)" HYDRA-1
   ```

   The last argument is the callsign shown on the detection dashboard; pick any.
   The script checks its own prerequisites and stops if anything is missing.
5. Verify:

   ```bash
   sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
   ```

   Expect 24 passes, 0 failures. One warning appears if the camera sees no
   recognizable object; put a person in frame and re-run to clear it.
6. Double-click **SORCC AI Kit** on the desktop: all three tools respond, the browser
   opens clean, Stop All releases RAM and the camera.
7. Delete `~/sorcc-stage/` and any transfer keys (full checklist in runbook step 10).

## Rules

- The LLM is `qwen3:4b-instruct`. Never `llama3.2:3b` (Meta license prohibits military
  use) and never plain `qwen3:4b` (thinking model, hangs instead of answering).
- One heavy tool at a time. 8 GB is not enough for two. The launcher enforces this;
  do not disable it.
- Keep ComfyUI images at 256 x 256. Bigger runs out of memory.
- Never `dd`-clone one Jetson's SD card to another. It copies the machine's identity
  and credentials. The retired clone method sits in `legacy-clone-method/`; don't use it.

## More detail

- `docs/provisioning-runbook.md` — the full procedure with every command and gate
- `docs/class-image-spec.md` — which features are enabled and which stay disabled
- `scripts/` — the installer, acceptance test, launcher, and ComfyUI workflows
- Hydra source: <https://github.com/rmeadomavic/Hydra>
