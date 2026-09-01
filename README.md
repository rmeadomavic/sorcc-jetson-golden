# sorcc-jetson-golden

Recipe, scripts, and acceptance procedure for the SORCC AI Kit: Jetson Orin Nano Super
student kits running Language (Ollama), Imagery (ComfyUI), and Detection (Hydra) behind
one launcher, one heavy tool at a time on 8 GB.

Use the current provisioning method. The superseded clone method stays for reference.

| Method | Approach | Where |
|---|---|---|
| **Current** | Provision each kit in place from the verified application payload. No raw disk clone. | `docs/`, `scripts/` |
| Legacy (superseded) | Golden SD image, `dd` clone, first-boot `student-setup.sh` | `legacy-clone-method/` |

The clone method was retired because cloning duplicates machine IDs, SSH host keys, and
stored credentials across kits. The current method installs the application payload
without copying identity or credential state between units.

## Start here

1. `docs/provisioning-runbook.md` is the procedure: identify the target, update
   firmware, stage the payload, finalize, run acceptance, clean up.
2. `docs/class-image-spec.md` defines the student-facing scope: what students touch,
   what ships disabled in config, and what stays off student kits entirely.
3. `scripts/sorcc-target-finalize.sh` does the per-unit install. It exits if any
   required artifact is missing.
4. `scripts/sorcc-jetson-smoke-test.sh` is the acceptance gate: 24 checks covering all
   three tools, the one-tool-at-a-time rule, and the Stop All control.

## Repo map

| Path | Purpose |
|---|---|
| `docs/provisioning-runbook.md` | Provisioning, acceptance, cleanup, and shutdown procedure |
| `docs/class-image-spec.md` | Student-facing Hydra scope, build spec, and RF boundary |
| `scripts/sorcc-target-finalize.sh` | Reusable per-unit finalizer (payload, services, callsign and token, desktop) |
| `scripts/sorcc-jetson-smoke-test.sh` | Per-kit software acceptance test |
| `scripts/sorcc_launcher.py` | Student launcher on port 8090. Pure stdlib, no venv. |
| `scripts/ollama_setup.sh` | Ollama install and `qwen3:4b-instruct` pull |
| `scripts/refresh_workflow_copy.py` | Applies approved student-facing text to the three included ComfyUI workflows |
| `scripts/workflows/` | The three curated ComfyUI workflows students see |
| `scripts/history/` | One-shot scripts already executed, kept as record. Host-locked. See its README. |
| `legacy-clone-method/` | The superseded clone recipe, unmodified |
| `assets/` | Bench-test source videos for camera-less detection testing |

## Constraints

- The LLM is `qwen3:4b-instruct`, swapped from `llama3.2:3b` on 2026-08-03 because the
  Meta acceptable-use policy prohibits military use. Never pull the plain `qwen3:4b`
  alias; it resolves to a thinking-only model that exhausts its output budget without
  answering.
- QSPI firmware is per-Jetson. No disk image or payload transfer carries it. Check and
  update both QSPI slots on every physical unit.
- 8 GB means one heavy tool at a time. The launcher enforces it; do not disable it.
- 256 by 256 is the ComfyUI memory guard, not a quality preference. SDXL and
  1024-pixel latents exhaust memory on these kits.
- The Hydra application pin is the container digest, not a git tag:
  `ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d`.
  Hydra source: <https://github.com/rmeadomavic/Hydra>.

## Not in this repo

Tailscale auth keys, account credentials, per-unit Hydra tokens, and instructor SSH
private keys. The finalizer generates each kit's token and prints only its hash, never
the token itself. The class Linux password is the standard classroom default printed on
the kit cards.
