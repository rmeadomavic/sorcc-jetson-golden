# Archive: old build methods (do not use)

Everything in this folder is kept as a record only. `install.sh` at the top of the repo
replaced all of it. Nothing here is needed to build a kit.

| Folder | What it was | Why it was retired |
|---|---|---|
| `payload-method/` | The 2026-07 method: copy a staged "payload" (`~/sorcc-stage/`, two Docker images, models, Ollama runtime) from an already-built Jetson, then run `sorcc-target-finalize.sh`. Includes the full provisioning runbook from that build. | Needed a working Jetson to copy from, and the ComfyUI image and several staged files could not be rebuilt from the repo. `install.sh` now builds everything from pinned public sources. |
| `legacy-clone-method/` | The 2026-04 method: `dd`-clone one SD card to every kit, then run `student-setup.sh`. | Cloning copies the source machine's identity and credentials. Its model choice (`llama3.2`) also violates the current license rule. |
| `history/` | One-shot cleanup and scrub scripts from the 2026-07 build, and the JetPack 7 prototype scripts. | Already ran. Host-locked to the original units. |

The JetPack 7 prototype in `history/jp7-prototype/` is where the "JetPack 7 containers cannot
reach the GPU (CUDA error 801)" finding came from. That finding is why the kit requires
JetPack 6.
