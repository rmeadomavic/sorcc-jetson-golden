# CLS 03-26 Jetson Class Image and Hydra Scope

The build and scope specification for the AI-module Jetson kits. Defines exactly what
Hydra surface students touch and what stays dark. The executable process is
`provisioning-runbook.md`.

> **The essence.** Hydra's job in the AI module is a live edge detector running offline
> on the platform, whose output students must interpret and distrust correctly, feeding
> the C2 picture they already know. Detection, then judgment, then C2. Everything else in
> the Hydra repo is R&D, not their course.

## Locked student-facing Hydra surface

The class standard is **OBSERVE mode: the payload watches and reports, it does not act.**
Ethos: verify, override, document. A high score is a cue to verify, not proof.

| Tier | What | Rationale |
|------|------|-----------|
| **Front-facing** (students run it) | YOLO detection + stable-ID tracking, dashboard at `:8080`, OBSERVE mode, MAVLink STATUSTEXT alerts to the FC | The only stack marked stable; matches the hands-on AI deck scope |
| **In image, dark** (config off; instructor may flip) | TAK/CoT out, `autonomous.enabled: false`, `rf_homing.enabled: false`, `drop.servo_channel: 0`, `servo_tracking.enabled: false`, `tak.listen_commands: false` | Student kits have no Alfa/RTL-SDR/FC-actuator wiring, so these show in Capability Status as hardware-blocked with honest reasons rather than being hidden |
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
| Base | JetPack 6.2.2, L4T R36.4.7, both QSPI slots at 36.4.7, MAXN_SUPER; preserve each unit's existing Linux account |
| Power | 4S vbat direct to Orin Nano DC input (9-20 V window); motors on a separate rail |
| LLM | `qwen3:4b-instruct` (swapped from `llama3.2:3b` on 2026-08-03; Meta AUP prohibits military use; never the plain `qwen3:4b` thinking alias) with the local streaming training UI: visible execution stages, token and timing metrics, session context, and a conditional reasoning panel |
| Imagery | Image `sha256:4e95d450bc7cee956786442302f632800515cd00d37bd1952d8c2ece3f085c5c`: PyTorch 2.7 + ComfyUI v0.19.3, `--lowvram --cpu-vae`, auto-loaded 256px START HERE workflow, quality workflow, SD 1.5 + DreamShaper 8 + RevAnimated + 5 LoRAs including LCM |
| Detector | Hydra digest `sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d` |
| RAM discipline | 8 GB kit: ONE heavy tool at a time. Stop the ComfyUI container before Ollama or the runner crashes (verified on bench) |

## The truck (SCX6): two honest tiers

- **Student scenario (cater to this, no more): mobile OP / perch-and-stare.** Drive the
  SCX6 to a vantage; watch detections live on the dashboard over CHIMERA Wi-Fi. A USB
  camera zip-tied to the truck works today. Zero new code.
- `hydra-detect.service` runs `docker run --rm --privileged`, not a `--device` map, so
  the container already reaches `/dev/ttyACM0`. Plugging in a Pixhawk needs no container
  or config change.
- **Instructor demo only: MAVLink STATUSTEXT alerts into the GCS** over the wired
  companion link (proven 2026-06-01). Stop there. No GUIDED-from-detections in front of
  students; Follow/Strike are hardware-test-gated.

## Build method: locked payload, per-device finalization

The original clone-first plan was not used. All three physical kits boot from their own
microSD cards and carry distinct hostnames and Linux accounts. Team3 became the verified
payload source. Team1 and Team2 were provisioned in place so their machine IDs, SSH host
keys, accounts, and CHIMERA profiles stayed unique.

The repeatable sequence:

1. Verify the target identity, root filesystem, storage health, and absence of personal
   credentials.
2. Upgrade L4T to 36.4.7 and update both QSPI slots on that physical Jetson. QSPI is not
   carried by a disk image.
3. Install and prove Chromium before finalization.
4. Transfer the locked application payload and both exact container images directly over
   the local network.
5. Run `sorcc-target-finalize.sh` with the target's existing Linux user and its `HYDRA-N`
   callsign. The script creates a unique token and installs the service, browser,
   launcher, wallpaper, and memory-policy state.
6. Run the full smoke script with the USB camera attached, then test the actual desktop
   shortcut and browser session.
7. Remove staging, transfer credentials, temporary registry data, test images, and
   personal state without removing the locked payload.

## Reproducibility pin

The deployed Hydra container digest is the authoritative application pin; no git tag
exists for it. The local ComfyUI image ID and the three workflow files in
`../scripts/workflows/` complete the pin set.

## Fleet closeout, 2026-07-22

- All three kits: issue-ready, 24 smoke passes, one covered manual warning, zero failures.
- Browser and desktop path passed on the actual shortcut with a clean local profile.
- Privacy pass: unique identity per kit; no Claude, Codex, or Tailscale state; transfer
  artifacts removed.
- Any future MMC or cache-flush error on a kit is a microSD replacement trigger.
