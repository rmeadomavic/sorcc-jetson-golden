# JetPack 7 build

The kit can be built on JetPack 7.2 or newer (Jetson Linux r38/r39, Ubuntu 24.04), the release
NVIDIA's download page now offers first. The JetPack 6 build stays available as the backup.

## How it differs from the JetPack 6 build

| | JetPack 7 | JetPack 6 (backup) |
|---|---|---|
| ComfyUI and Hydra | Run natively from one Python environment, `/opt/sorcc/venv` | Run in Docker |
| PyTorch | 2.11 for CUDA 13.0, the official pytorch.org ARM build | 2.7 (ComfyUI image) and 2.4 (Hydra image), Jetson builds for CUDA 12.6 |
| Code | ComfyUI v0.19.3 and Hydra `405eaf8` in `/opt/sorcc/app/` | Same versions, inside the images |
| Pins | `jetpack7/requirements.lock` | `comfyui/Dockerfile`, `comfyui/requirements.lock`, Hydra image digest |
| Same on both | Launcher, service names, ports, `/opt/sorcc/comfyui` and `/opt/sorcc/hydra` data, models, workflows, class config, smoke test | |

The JetPack 6 Docker images cannot use the GPU on JetPack 7 (their CUDA 12.6 cannot talk to
the JetPack 7 driver; CUDA error 801). That is why JetPack 7 does not use Docker at all.

## The JetPack 7 test

Run it once, on one Jetson, before building kits:

```bash
sudo ./scripts/jetpack7-test.sh
```

| Check | Passes when |
|---|---|
| Super mode | MAXN_SUPER is available and the GPU can reach about 1020 MHz. Only a warning if not: everything works, just slower. |
| GPU math | PyTorch sees the GPU, and matrix and convolution results in fp32 and fp16 match the CPU. Wrong or NaN GPU math is what causes blank images. |
| Imagery | ComfyUI renders the real START HERE workflow (DreamShaper 8 + LCM, 256 px, 4 steps) on the GPU and the picture is not blank. |
| Detection | YOLOv8n runs on the GPU over the sample video at 10 FPS or more and finds people. |

It uses the same environment and models as `install.sh`, so the downloads are not wasted, and
it leaves no services running. The full output is in `/var/log/sorcc-jetpack7-test.log`, and the
rendered test picture is in `/opt/sorcc/comfyui/output/`.

If it recommends the JetPack 6 backup, reflash with [reflash-jetpack6-nvme.md](reflash-jetpack6-nvme.md).

## Super mode

Super mode (MAXN_SUPER) raises the GPU from 624 MHz to 1020 MHz. Check it with:

```bash
grep -o 'NAME=MAXN_SUPER' /etc/nvpmodel.conf    # prints NAME=MAXN_SUPER when Super mode is available
sudo nvpmodel -q                                # shows the current mode
```

The JetPack 7.2 USB/ISO installer leaves Super mode off on the Orin Nano dev kit, so a kit
installed that way only has the 7 W and 15 W modes and the GPU stays at 624 MHz. NVIDIA
acknowledged this on their forum and said it would be fixed in JetPack 7.2.1. Ways to get it:

1. **Install JetPack 7.2.1 or newer** with NVIDIA's current USB installer (NVIDIA's stated fix;
   not yet confirmed by users).
2. **Flash with SDK Manager or NVIDIA's command-line flash** from an Ubuntu PC, using the Orin
   Nano dev kit *Super* configuration (`jetson-orin-nano-devkit-super`). NVIDIA staff confirmed
   this gives Super mode on both JetPack 6 and 7.
3. Forum users describe an in-place fix (switching the boot configuration to the `-super-`
   variant). NVIDIA has not confirmed it, so use it only if you are comfortable recovering a
   Jetson by reflashing.

Without Super mode the kit still works; images and detection are just slower. `install.sh`
switches to MAXN_SUPER by itself when it is available.

## Not proven yet

- JetPack 7 has not been through a class. The test is the evidence; please keep its log.
- The pytorch.org CUDA 13 build runs Orin (sm_87) code through its sm_80 kernels. NVIDIA staff
  say that is expected to work, and the GPU math check verifies it on each kit.
- One community guide reported blank ComfyUI images on JetPack 7.2. The kit decodes images on
  the CPU (`--cpu-vae`), which avoids the usual cause, and the test checks the real output.

Sources: NVIDIA forum threads "JetPack 7.2 / L4T 39.2 — GPU frequency stuck at 624 MHz on
Orin Nano", "25w and MAXN SUPER not seen in jetpack 7.2", and "Orin AGX, JP 7.2, Pytorch and
sm_87 support" (June to July 2026).

## Updating the pinned packages

Only when moving to new versions. `jetpack7/requirements.in` lists the top-level packages.
With [uv](https://docs.astral.sh/uv/):

```bash
uv pip compile jetpack7/requirements.in --python-version 3.12 \
  --python-platform aarch64-unknown-linux-gnu \
  --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/cu130 \
  --index-strategy unsafe-best-match --exclude-newer <YYYY-MM-DD> \
  --no-header --no-annotate -o /tmp/requirements.lock
```

Then delete the `opencv-python==` line (Hydra uses the headless build), keep the header of
`jetpack7/requirements.lock`, and replace the rest. Run the JetPack 7 test again afterward.
