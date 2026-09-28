# Jetson Class Image and Hydra Scope

The build and scope specification for the AI-module Jetson kits. Defines exactly what
Hydra surface students touch and what stays dark. The executable process is `install.sh`
(see the [README](../README.md)).

> **The essence.** Hydra's job in the AI module is a live edge detector running offline
> on the platform, whose output students must interpret and distrust correctly, feeding
> the C2 picture they already know. Detection, then judgment, then C2. Everything else in
> the Hydra repo is R&D, not their course.

## Locked student-facing Hydra surface

The class standard is **OBSERVE mode: Hydra watches and reports, it does not act.**
Ethos: verify, override, document. A high score is a cue to verify, not proof.

| Tier | What | Rationale |
|------|------|-----------|
| **Front-facing** (students run it) | YOLO detection + stable-ID tracking, dashboard at `:8080`, OBSERVE mode, MAVLink STATUSTEXT alerts to the FC | The only stack marked stable; matches the hands-on AI deck scope |
| **In image, dark** (config off; instructor may flip) | TAK/CoT out (`tak.enabled: false`), `autonomous.enabled: false`, `rf_homing.enabled: false`, `drop.servo_channel: 0`, `servo_tracking.enabled: false`, `tak.listen_commands: false` | Student kits have no Alfa/RTL-SDR/FC-actuator wiring, so these show in Capability Status as hardware-blocked with honest reasons rather than being hidden |
| **Never surfaces** | Follow/Strike/radial menu, HDZero OSD overlay, OTA, phone-home, OpenMANET, Hydra Lite | All carry explicit untested/gated/in-design language upstream. Untested promises do not ship to students |

> **Why this is not a fork or a feature-strip.** One codebase, one class config profile.
> Features gate by system state (no camera means no detections; no FC means no vehicle
> commands; no SDR means RF blocked), not by a stripped student build. Operators are not
> walled off; the untested surface just stays off their screen.

## RF boundary

Student-facing RF hunting belongs to the Argus RPi payload and the Kismet-on-Raspberry-Pi
lanes, not Hydra. Hydra's RF-homing branch is demo-grade and disabled in field images.
Turning it on would double-book Kismet (`:2501` on both stacks), duplicate a lane with
demo code, and blur the module boundary students are being taught.

## Class image build spec

| Layer | Locked value |
|-------|--------------|
| Base | JetPack 7.2+ (Jetson Linux r39, Ubuntu 24.04), native build, once `scripts/jetpack7-test.sh` passes; backup JetPack 6.2.x (Jetson Linux 36.4.3 or newer within R36, Ubuntu 22.04), Docker build. One version per class. NVMe or microSD, MAXN_SUPER; each unit keeps its own Linux account. JetPack 7 cannot run the JetPack 6 containers (CUDA error 801), so it uses no Docker |
| Power | 4S vbat direct to Orin Nano DC input (9-20 V window); motors on a separate rail |
| LLM | Ollama 0.34.4, CPU only, 4K context, `qwen3:4b-instruct` (swapped from `llama3.2:3b` on 2026-08-03; Meta AUP prohibits military use; never the plain `qwen3:4b` thinking alias) with the local streaming training UI: visible execution stages, token and timing metrics, session context, and a conditional reasoning panel |
| Imagery | ComfyUI v0.19.3. JetPack 7: native in `/opt/sorcc/venv` (PyTorch 2.11, CUDA 13.0, `jetpack7/requirements.lock`). JetPack 6: `comfyui-sorcc:latest`, built on each kit from `comfyui/Dockerfile`: `dustynv/pytorch:2.7-r36.4.0` (PyTorch 2.7, CUDA 12.6) + `comfyui/requirements.lock`. Both run with `--lowvram --cpu-vae --disable-dynamic-vram`; auto-loaded 256px START HERE workflow, quality workflow, cheat sheet; SD 1.5 + DreamShaper 8 + RevAnimated 1.2.2 + 5 LoRAs including LCM (`comfyui/models.txt`) |
| Detector | JetPack 7: Hydra commit `405eaf8` native in `/opt/sorcc/venv`. JetPack 6: Hydra digest `sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d` (built from Hydra commit `405eaf8`), YOLOv8n weights, class config `hydra/config.ini` |
| RAM discipline | 8 GB kit: ONE heavy tool at a time. Stop ComfyUI before Ollama or the runner crashes (verified on bench) |

## The truck (SCX6): two honest tiers

- **Student scenario (cater to this, no more): mobile OP / perch-and-stare.** Drive the
  SCX6 to a vantage; watch detections live on the dashboard over CHIMERA Wi-Fi. A USB
  camera zip-tied to the truck works today. Zero new code.
- `hydra-detect.service` runs as root (JetPack 7) or `docker run --rm --privileged` (JetPack 6),
  not a `--device` map, so Hydra already reaches `/dev/ttyACM0`. Plugging in a Pixhawk needs no
  service or config change.
- **Instructor demo only: MAVLink STATUSTEXT alerts into the GCS** over the wired
  companion link (proven 2026-06-01). Stop there. No GUIDED-from-detections in front of
  students; Follow/Strike are hardware-test-gated.

## Build method: per-kit install from pinned sources

The original clone-first plan was not used, and the 2026-07 copy-from-a-finished-kit method
is retired (see `archive/`). Each kit now builds itself with `install.sh`, so it keeps its own
hostname, Linux account, machine ID, SSH host keys, and network profile.

The repeatable sequence:

1. Run `sudo ./scripts/jetpack7-test.sh` on one kit. If it passes, build every kit on
   JetPack 7.2+; if not, reflash every kit to JetPack 6.2.x (`docs/reflash-jetpack6-nvme.md`).
2. Run `sudo ./install.sh HYDRA-N` with the kit's callsign. It installs Chromium, Super mode,
   Ollama and the model, Hydra and ComfyUI (JetPack 7: pinned sources and one Python
   environment; JetPack 6: Docker, the NVIDIA runtime, the pinned Hydra image, and the ComfyUI
   image), and the checked models; creates a unique Hydra token; and installs the services,
   one-tool policy, launcher, wallpaper, and desktop shortcut.
3. Reboot, then run the smoke test with the USB camera attached.
4. Check the actual desktop shortcut and browser session (`docs/acceptance-checklist.md`).

## Reproducibility pin

Everything a kit runs is pinned in this repo:

- Hydra: commit `405eaf8` in `scripts/sorcc-lib.sh` (JetPack 7), container digest above (JetPack 6)
- JetPack 7 Python packages: `jetpack7/requirements.lock`; ComfyUI commit in `scripts/sorcc-lib.sh`
- ComfyUI (JetPack 6): base image digest and ComfyUI commit in `comfyui/Dockerfile`, Python packages in
  `comfyui/requirements.lock`, model files by SHA-256 in `comfyui/models.txt`, and the three
  workflows in `comfyui/workflows/`
- Language: `OLLAMA_VERSION` and `LLM_MODEL` at the top of `install.sh`

Units built to this spec are issued to students and leave with them at the end of the
course. Any MMC or cache-flush error on a microSD unit is a card replacement trigger.
