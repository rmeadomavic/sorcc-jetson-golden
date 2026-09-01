# sorcc-jetson-golden

Recipe, scripts, and acceptance procedure for the SORCC AI Kit: Jetson Orin Nano Super
student kits running Language (Ollama), Imagery (ComfyUI), and Detection (Hydra) behind
one launcher, one heavy tool at a time on 8 GB.

Two methods live here. Use the current one.

| Method | Approach | Where |
|---|---|---|
| **Current** | In-place provisioning from a locked payload. No raw disk clone. | `docs/`, `scripts/` |
| Legacy (superseded) | Golden SD image + `dd` clone + first-boot `student-setup.sh` | `legacy-clone-method/` |

Do not build a new fleet from the clone method. It was replaced because cloning carries
machine IDs, SSH host keys, and credentials to every kit. The current method preserves
each target's identity and provisions the application payload onto it.

## Start here

1. `docs/provisioning-runbook.md` is the executable procedure: identify the target,
   bring firmware to baseline, stage the payload, finalize, run acceptance, clean up.
2. `docs/class-image-spec.md` defines the student-facing scope: what students touch,
   what ships dark in config, and what never surfaces.
3. `scripts/sorcc-target-finalize.sh` does the per-unit install. It generates a unique
   Hydra token per kit and refuses to run with missing artifacts.
4. `scripts/sorcc-jetson-smoke-test.sh` is the acceptance gate: 24 checks across all
   three tools, exclusivity, and Stop All.

## Repo map

| Path | Purpose |
|---|---|
| `docs/provisioning-runbook.md` | Canonical provisioning, acceptance, cleanup, and shutdown procedure |
| `docs/class-image-spec.md` | Student-facing Hydra scope, build spec, and RF boundary |
| `scripts/sorcc-target-finalize.sh` | Reusable per-unit finalizer (payload, services, identity, desktop) |
| `scripts/sorcc-jetson-smoke-test.sh` | Per-kit software acceptance test |
| `scripts/sorcc_launcher.py` | The student front door on `:8090`. Pure stdlib, no venv. |
| `scripts/ollama_setup.sh` | Ollama install + `qwen3:4b-instruct` pull |
| `scripts/refresh_workflow_copy.py` | Applies reviewed student copy to the three shipped ComfyUI workflows |
| `scripts/workflows/` | The three curated ComfyUI workflows students see |
| `scripts/history/` | Executed one-shot scripts, kept as record. Host-locked. See its README. |
| `legacy-clone-method/` | The full superseded clone recipe, unmodified |
| `assets/` | Bench-test source videos for camera-less detection testing |

## Facts that bite

- **The LLM is `qwen3:4b-instruct`.** Swapped from `llama3.2:3b` on 2026-08-03 because
  the Meta AUP prohibits military use. Never pull the plain `qwen3:4b` alias; it
  resolves to a thinking-only model that exhausts its output budget without answering.
- **QSPI firmware is per-Jetson.** No disk image or payload transfer carries it. Check
  and update both slots on every physical unit.
- **8 GB means one heavy tool at a time.** The launcher enforces it. Do not "fix" this.
- **256 by 256 is the ComfyUI memory guard**, not a quality preference. SDXL and
  1024-pixel latents exhaust memory on these kits.
- The Hydra application pin is the container digest, not a git tag:
  `ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d`.
- Hydra source: <https://github.com/rmeadomavic/Hydra>.

## What is deliberately not here

No Tailscale authkeys, no account credentials, no per-unit Hydra tokens, no instructor
SSH private keys. Per-unit tokens are generated at finalize time and reported only as a
hash. The class Linux password is the standard classroom default and is printed on the
kit cards, not managed here.
