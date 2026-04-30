# sorcc-jetson-golden

Recipe and operator notes for the SORCC Class 02-26 Jetson Orin Nano Super
golden SD card image. **This repo is the source of truth — the binary
image is regenerable from these scripts and pinned references.**

## What's in here

| File | Purpose |
|---|---|
| `student-setup.sh` | First-boot script run on each cloned student Jetson. Sets hostname, static IP, installs Docker/Ollama/Tailscale, applies hardening. Idempotent. |
| `pre-clone-wipe.sh` | Run on the golden image immediately before pulling the SD card for cloning. Wipes machine-id, SSH host keys, shell history, GNOME caches, etc. `DRY_RUN=1` previews. |
| `jetson-hardening/` | Drop-in configs + `apply-hardening.sh` baseline (journald cap, Docker live-restore, swap, udev rules for SDR + autopilot, `sorcc-diag` collector). Wired into `student-setup.sh` section B.6. |
| `CLONING.md` | Step-by-step procedure: wipe golden → `dd` to image → flash student cards → first-boot setup. |
| `PRE-CLONE-TODO.md` | Open decisions before the next clone run + session-by-session changelog of what was added/fixed on the golden image. |
| `STUDENT-README.md` | The `README.md` that ships *on* the student SD card (gets symlinked to `~/README.md` on the Jetson). |

## Symlinks on the live Jetson

These files live in this directory but are symlinked into `/home/sorcc/`
so existing absolute paths (`/home/sorcc/student-setup.sh`,
`/home/sorcc/pre-clone-wipe.sh`, etc.) keep working:

```
/home/sorcc/student-setup.sh    -> sorcc-jetson-golden/student-setup.sh
/home/sorcc/pre-clone-wipe.sh   -> sorcc-jetson-golden/pre-clone-wipe.sh
/home/sorcc/CLONING.md          -> sorcc-jetson-golden/CLONING.md
/home/sorcc/PRE-CLONE-TODO.md   -> sorcc-jetson-golden/PRE-CLONE-TODO.md
/home/sorcc/jetson-hardening    -> sorcc-jetson-golden/jetson-hardening
/home/sorcc/README.md           -> sorcc-jetson-golden/STUDENT-README.md
```

`pre-clone-wipe.sh` should leave these symlinks intact — verify if you
edit the wipe script.

## External references (not vendored here)

| Thing | Where | Notes |
|---|---|---|
| Hydra Detect repo | https://github.com/rmeadomavic/Hydra | Cloned by `student-setup.sh`. **TODO:** pin to a specific SHA so future Hydra changes don't silently alter the student experience. |
| `jetson-orin-servo/` | `/home/sorcc/jetson-orin-servo/` (own git repo) | Hardware PWM fix for the 40-pin header. Referenced from `PRE-CLONE-TODO.md` item 3. |
| `dustynv/l4t-pytorch:r36.4.0` | Docker Hub | Pinned tag. Pre-pulled on golden image. |
| `hydra-detect:latest` | Built locally on golden image | Built from the Hydra repo at clone time. **TODO:** tag with the Hydra SHA at build time so it's traceable. |
| `llama3.2:1b` | Ollama registry | Pulled by `student-setup.sh`. Tag is unpinned. |
| `yolov8n.engine` | `~/Hydra/models/yolov8n.engine` on golden image | FP16 TensorRT engine, ~9 MB. Rebuild if JetPack TRT version changes. |

## Known floats (things that can drift)

These are dependencies that are *not* pinned to a specific version. If
upstream changes, the golden image build can break or behave
differently. Worth tightening before the next class:

- Hydra repo HEAD (`student-setup.sh` does an unpinned `git clone`)
- `apt` package versions for `cloud-guest-utils`, `btop`, `v4l-utils`,
  Docker, Tailscale (whatever Ubuntu repos serve that day)
- Ollama model tag `llama3.2:1b`
- `pip install` lines inside `hydra-setup.sh` (chained from
  `student-setup.sh` after Hydra is cloned)

## Regenerating the image from scratch

Rough procedure for "the golden card died, rebuild it":

1. Flash a fresh JetPack 6 SD card via NVIDIA SDK Manager.
2. Boot, log in as `sorcc`/`sorcc`.
3. Clone this repo into `~/sorcc-jetson-golden/`.
4. Re-create the symlinks listed above.
5. Run `sudo bash student-setup.sh` (it'll do the same thing it does on
   a student card — that's by design; the golden image *is* a
   pre-cloned student image with cached apt/docker/model state).
6. Pull the demos, ComfyUI, jetson-orin-servo, and any Drive-hosted
   artifacts back down.
7. Reboot, smoke-test, run `pre-clone-wipe.sh`, image, clone.

This procedure is incomplete — there's setup state on the live image
that's not yet in any script (ComfyUI install, Claude Code install,
demos, the `jetson-orin-servo/` clone, etc.). Building a real
end-to-end `bootstrap.sh` is the next-level-up version of this repo.

## Updating this repo

Whenever you change something on the golden image that should persist
into future clones — installed a package, tweaked a config, fixed a
bug — commit it here. The repo is only useful if it stays in sync with
the live image.
