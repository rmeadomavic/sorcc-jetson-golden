# Executed one-shot scripts (record only)

Everything in this directory already ran. It is kept as a worked example and audit
record, not as a tool to re-run. The cleanup and scrub scripts are host-locked by
hostname check and magic argument, and they assert against the exact 2026-07-22 fleet
state. Their SHA-256 hashes are pinned in `../../docs/provisioning-runbook.md`.

| Script | What it did |
|---|---|
| `team1-post-provision-cleanup.sh` | Removed Team1 provisioning duplicates after acceptance |
| `team2-post-provision-cleanup.sh` | Removed Team2 provisioning duplicates, temp registry, and fsck boot artifacts |
| `team3-post-provision-cleanup.sh` | Removed Team3 test models, superseded images, caches, and bench output |
| `team3-final-scrub.sh` | Destructive privacy and identity scrub of the former instructor build box; rotated machine ID and SSH host keys |
| `jp6_base_super.sh` | Early JP6.2.2 base prep. Superseded: it pins `jetson_clocks` and adds a 16 GB file swap, both of which the final runbook forbids |

`jp7-prototype/` holds the JetPack 7 native-stack experiment from the `sorcc1` box:
venv-based ComfyUI/Hydra installs, Ollama benchmarks, and the first launcher deploy.
That box proved JP7 containers cannot reach the GPU (CUDA error 801), which is why the
fleet ships JetPack 6 with Docker images instead. None of it matches the deployed fleet;
read it for the reasoning, not the commands. Its bench script pulls `llama3.2:3b`, which
predates the 2026-08-03 model policy and must not be used in class.
