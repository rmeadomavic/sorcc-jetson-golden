# SORCC Jetson Provisioning Runbook

Instructor runbook for building the SORCC AI Kit on Jetson Orin Nano Super developer
kits. Written 2026-07-22 during the original build; updated 2026-09-01 for the
qwen3:4b-instruct model swap. Units built from this runbook are issued to students and
leave with them, so every build is a fresh one; keep one provisioned unit back as the
payload source for the next round. The student-facing scope lives in
`class-image-spec.md`.

> **Proven rollout method.** Provision each target **in place from the locked payload**.
> Do not raw-clone the source microSD. In-place provisioning preserves the target
> hostname, Linux account, machine ID, SSH host keys, and network profile. It also avoids
> cloning credentials and browser state. QSPI firmware lives on each Jetson and must be
> checked per device regardless of how the root filesystem is populated.

## Target baseline

Every finished unit meets this state: JetPack 6.2.2 / L4T 36.4.7, QSPI 36.4.7 in both
normal slots, MAXN_SUPER, a 1020 MHz GPU maximum, 128 GB-class microSD root, no NVMe.
Each unit keeps its own hostname and Linux account and gets a unique `HYDRA-N` callsign.
The payload source is an already-provisioned unit; it is never a disk-clone source.

## Locked application payload

| Layer | Required state |
|---|---|
| Launcher | `/opt/sorcc/sorcc_launcher.py`, enabled at port 8090, with Stop All |
| Language | Ollama CPU fallback, complete `llama-server` runtime, `qwen3:4b-instruct` |
| Imagery | `comfyui-sorcc:latest`, image ID `sha256:4e95d450bc7cee956786442302f632800515cd00d37bd1952d8c2ece3f085c5c` |
| Detection | `ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d` |
| Detection weights | `/opt/sorcc/hydra/models/yolov8n.pt`, 6,549,796 bytes |
| ComfyUI | v0.19.3, PyTorch 2.7, `--lowvram --cpu-vae`, 256 by 256 output |
| Models | Three checkpoints, five LoRAs, three curated workflows |
| Browser | Chromium, clean local-only profile, explicit HTTP/HTTPS/HTML default |
| Desktop | Trusted SORCC AI Kit shortcut and centered SORCC logo on black |
| Runtime policy | One heavy tool at a time; Ollama, ComfyUI, and Detection are on demand |

**Model note.** The class LLM is `qwen3:4b-instruct`, swapped from `llama3.2:3b` on
2026-08-03 because the Meta AUP prohibits military use. Never pull the plain `qwen3:4b`
alias: on 2026-07-21 it resolved to a thinking-only model that repeatedly exhausted its
output budget without answering. The launcher, `ollama_setup.sh`, the smoke test, and the
finalizer in this repo all carry the instruct model.

## 1. Connect and identify the physical target

1. Connect the target to the CHIMERA router by Ethernet when possible.
2. Attach the Logitech C270 before acceptance.
3. Find both Ethernet and Wi-Fi leases. Treat IP addresses as discovery hints only.
4. Read and verify the ED25519 host-key fingerprint before adding or replacing a local
   `known_hosts` entry.
5. Log in with the account already created on that physical box. Do not rename a working
   account to fit an old note.

Workstation fingerprint check:

```powershell
ssh-keyscan -t ed25519 <target-ip> 2>$null | ssh-keygen -lf -
```

Target identity and storage check:

```bash
hostnamectl --static
id
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
ip -brief address
nmcli -t -f NAME,TYPE connection show
```

Hard stop if the hostname, user, host key, or root device does not match the intended
physical unit.

## 2. Preflight before large writes

```bash
df -h /
findmnt -no OPTIONS /
systemctl --failed --no-pager
sudo dmesg -T | grep -Ei 'mmc|I/O error|cache flush|journal.*abort|ext4.*error' || true
test ! -e /run/reboot-required
```

Required before provisioning:

- root is mounted read-write
- no active MMC, I/O, journal, or ext4 error
- no unexplained failed systemd unit
- enough free space for the staged payload and both large container images
- target has its own machine ID and SSH host keys
- no unexpected Claude, Codex, Tailscale, keyring, or browser-account state

Do not repair a mounted root filesystem. Any future MMC or cache-flush error on a
provisioned unit is a microSD replacement trigger, not a repair job.

## 3. Bring L4T and both QSPI slots to the baseline

Update the root filesystem first, then reboot and inspect the actual running state:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

```bash
head -1 /etc/nv_tegra_release
sudo nvbootctrl dump-slots-info
test ! -e /run/reboot-required
systemctl --failed --no-pager
```

A recurring NVIDIA reboot notice is caused by L4T 36.4.7 on microSD while QSPI remains
at 36.4.4. The package hook silently fails because the 64 MB EFI partition lacks the
scratch space requested by `fwupdtool`. Use NVIDIA's direct capsule helper instead:

```bash
sudo nv_bootloader_capsule_updater.sh -q /opt/ota_package/t23x/TEGRA_BL_3767_super.Cap
sudo reboot
```

Run it once from each active slot, rebooting after each run, until `nvbootctrl` reports:

- QSPI 36.4.7 in slots A and B
- both slots normal
- slot B current and active
- no persistent reboot marker

QSPI is per Jetson. A disk image cannot carry this update to another unit.

Set and verify Super mode without pinning `jetson_clocks`:

```bash
sudo nvpmodel -m 2
sudo nvpmodel -q
cat /sys/devices/17000000.gpu/devfreq/17000000.gpu/max_freq
```

Expected GPU maximum is `1020000000`. Do not ship a permanent file swap. The runtime uses
zram, volatile journald, and memory compaction before GPU services.

## 4. Install and prove the browser before finalization

The finalizer intentionally refuses to continue without Chromium. This gate exists
because two kits originally had valid desktop shortcut files but no browser capable of
opening them.

```bash
sudo snap install chromium --channel=latest/stable
snap list chromium snapd
sudo snap refresh --hold snapd
snap refresh --time
test -x /snap/bin/chromium
```

Verified on 2026-07-22: Chromium 150.0.7871.128 revision 3498 with snapd 2.76 revision
27407. Retain a newer working revision rather than automatically downgrading it.

If snapd itself is broken, the known fallback is a manual revision 24724 sideload. Use
this only as recovery, not as the normal path:

```bash
snap download snapd --revision=24724
sudo snap ack snapd_24724.assert
sudo snap install snapd_24724.snap
sudo snap refresh --hold snapd
```

## 5. Stage the locked payload

Work under the target user's home at `~/sorcc-stage`. The reusable finalizer hard-fails
if any required artifact is missing. The minimum tree is:

```text
sorcc-stage/
├── comfyui/
│   ├── custom_nodes/sorcc_student/
│   ├── models/checkpoints/
│   ├── models/loras/
│   ├── user/
│   └── workflows/
├── hydra/
│   ├── config.ini
│   └── models/yolov8n.pt
├── ollama/
│   ├── ollama
│   ├── lib/llama-server
│   └── models/manifests/registry.ollama.ai/library/qwen3/4b-instruct
├── sorcc_launcher.py
├── sorcc-jetson-smoke-test.sh
└── sorcc-wallpaper.png
```

Transfer directly over the local LAN from an existing kit or an instructor-controlled
artifact copy. Do not relay multi-gigabyte image streams through a laptop or through two
Tailscale hops; that path stalls. A temporary local registry or direct source-to-target
transfer is fine; remove its data and transfer key during cleanup.

Before finalization, both container pins must already resolve locally:

```bash
docker image inspect --format '{{.Id}}' comfyui-sorcc:latest
docker image inspect 'ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d'
```

Never copy a source kit's Hydra token or callsign into a target. The finalizer generates
a fresh token, sets the requested callsign, and scrubs the reusable staged config back to
placeholders.

## 6. Run the reusable finalizer

Authoritative copy: `scripts/sorcc-target-finalize.sh` in this repo.

Review the script and transfer it to the target. Then run:

```bash
chmod +x ./sorcc-target-finalize.sh
sudo ./sorcc-target-finalize.sh "$(id -un)" HYDRA-N
```

Replace `N` with the physical team number. A successful run ends with `FINALIZE_OK` and a
token hash, never the token itself.

The finalizer installs the application payload, offline Ollama runtime, CPU fallback,
systemd services, one-tool exclusivity, memory compaction, volatile journald, browser
defaults, desktop shortcut, black SORCC wallpaper, per-unit callsign, and unique Hydra
token. It enables only Docker and the launcher at boot. The three heavy tools remain
on-demand.

## 7. Privacy and identity pass

Clean targets keep their existing hostname, Linux account, machine ID, SSH host keys, and
CHIMERA profile. Remove only provisioning state and anything that belongs to an
instructor or source box.

Audit at minimum:

```bash
find "$HOME" -maxdepth 3 \( -name '.claude*' -o -name '.codex*' -o -iname '*tailscale*' \) -print
dpkg-query -W tailscale 2>/dev/null || true
test ! -e /var/lib/tailscale
find "$HOME/.ssh" -maxdepth 1 -type f -print 2>/dev/null
find "$HOME/.local/share/keyrings" -mindepth 1 -print -quit 2>/dev/null
```

Rules:

- no Claude OAuth, session, MCP, local binary, URL handler, or site data
- no Codex state
- no Tailscale package or node identity
- no source-box transfer key
- only the explicitly approved instructor public key remains, if current doctrine still
  requires it
- browser profile contains no non-local history, login, autofill, payment, account, or
  cookie data
- machine ID, SSH host keys, and Hydra token are unique per unit
- CHIMERA remains present before removing any alternate remote-access path

The scrub and cleanup scripts in `scripts/history/` are host-locked one-shots from the
original build. They show the shape of a correct scrub (the full scrub exists because the
source unit had been an instructor build box). Review and adapt; never run one unchanged
on a different hostname.

## 8. Run software acceptance

With the USB camera connected:

```bash
sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
```

The script expects 24 passes, zero failures, and may emit one manual warning when no
recognizable object is in frame. It proves:

- L4T and MAXN state
- camera node and live JPEG
- offline YOLO weights and dark Hydra gates
- exact streaming Language response and metrics
- ComfyUI v0.19.3 runtime flags
- a real PNG from the shipped START HERE workflow
- curated workflow publication and auto-loading
- one-tool exclusivity in all three modes
- Stop All leaves every heavy service inactive and no failed unit
- Detection is restored before exit

An acceptance test must assert expected content and output files. Do not treat an empty
log or the absence of an error string as a pass.

## 9. Perform the physical desktop acceptance

This is mandatory even after the smoke script. The missing-browser defect passed the old
shortcut-file check.

1. Use the logged-in physical desktop session.
2. Confirm the centered SORCC logo on solid black.
3. Double-click `SORCC AI Kit`.
4. Confirm Chromium opens directly to the local launcher with no first-run, login, sync,
   or default-browser prompt.
5. Confirm the launcher shows Language, Imagery, Detection, resource status, and Stop All.
6. On Language, verify both Enter and Send submit a prompt and that streaming stages and
   completion metrics update.
7. On Imagery, verify the START HERE workflow opens automatically and retains the locked
   256-pixel, four-step LCM preset.
8. On Detection, view the actual camera image and overlay. Put a person in frame when a
   stable tracking demonstration is required; confirm the box, label, and stable track ID.
9. Use Stop All and confirm RAM and camera resources are released without stopping the
   launcher.

Record what was actually observed. A healthy ceiling or room view is a camera check, not
a tracking test; log the distinction.

## 10. Cleanup after acceptance

Stop the heavy tools, then remove only reviewed provisioning duplicates:

```bash
curl -fsS -X POST http://127.0.0.1:8090/stop
```

Cleanup checklist:

- remove `~/sorcc-stage`
- remove any temporary local registry and its data
- remove generated acceptance PNGs and screenshots
- remove temporary filesystem-check boot artifacts
- remove apt cache and Docker build cache not needed by the locked images
- remove the source transfer key
- retain the exact ComfyUI image, Hydra digest, workflows, model files, wallpaper, and
  approved instructor key
- remove root copies of cleanup scripts after their assertions pass
- truncate or remove instructor login traces according to the privacy audit
- run `sync`

The guarded host-specific cleanup scripts from the original rollout are in
`scripts/history/` as worked examples. Write a new reviewed script per target; do not
substitute an unreviewed recursive delete for allowlisted paths.

## 11. Final issue gate

| Gate | Required result |
|---|---|
| Root filesystem | read-write; no new MMC, I/O, journal, or ext4 error |
| Firmware | L4T 36.4.7; QSPI 36.4.7 in both normal slots; no reboot marker |
| Power | MAXN_SUPER; GPU maximum 1020 MHz; no permanent `jetson_clocks` pin |
| Services | launcher and Docker active; zero failed units; heavy tools on demand |
| Privacy | no Claude, Codex, Tailscale, source transfer state, or personal browser data |
| Identity | correct unique host, account, machine ID, SSH keys, callsign, and token |
| Browser | actual desktop shortcut opens clean local Chromium profile |
| Language | exact streaming pass response; Enter and Send work |
| Imagery | real 256 by 256 PNG from START HERE workflow in roughly 40 to 60 seconds |
| Detection | healthy live C270 image; roughly 31 to 39 FPS on accepted units |
| Controls | one heavy tool at a time; Stop All works |
| Student copy | professional bench language; no developer register; GENERATED rule stays in Imagery context |

Do not issue the unit until every applicable gate is closed or the course lead explicitly
accepts the remaining manual observation.

## 12. Clean shutdown

```bash
sync
sudo systemctl poweroff
```

Wait for SSH to disappear and the board to complete shutdown before removing power.
Record which physical team was powered down; do not infer it from a stale DHCP lease.

## Known-good measurements

Accepted units measured 34 to 38 FPS detection at 23 to 26 ms inference, 46 to 50 second
START HERE renders, and 24 acceptance passes with one manual warning and zero failures.
These are microSD systems. NVMe improves cold-load and filesystem responsiveness but does
not change the required 256-pixel ComfyUI memory guard.

## Script hashes

Hashes of the scripts as deployed and executed on 2026-07-22:

| Script | SHA-256 on 2026-07-22 |
|---|---|
| `sorcc-target-finalize.sh` | `49b718d1face1f806e5b9c81d6809f84e64751b5fec8425b9c5cd0d25dcc9b19` |
| `team1-post-provision-cleanup.sh` | `eb3982c7a15c7414510f1a0fab3e9486be25aef81bdc6465ea7b1b013c09fdfe` |
| `team2-post-provision-cleanup.sh` | `b9f6109e2ba07cdac0eaab29540dfd95ba4dc7ea7ba6db2743e49697438e2bde` |
| `team3-final-scrub.sh` | `31081f4f83a5f9a623acf0b32b219a2d479c4b31c22fd68ca51a55f0630ce527` |
| `sorcc-jetson-smoke-test.sh` | `3ebb056790fa3e85a382cc65ab1c19e4d25ad94e7ba4d2e3368769bda2958aa4` |

The `scripts/history/` copies of the cleanup and scrub scripts match these hashes
byte-for-byte. Two current scripts have moved past the 2026-07-22 record:

- `scripts/sorcc-jetson-smoke-test.sh` now hashes
  `b61b7ead9d8c0a6469e6c074ecffe9a59f927e2a263881c74756c01a260d09d2`. The 2026-08-03
  qwen-swap version that ran the re-acceptance hashed
  `6a4479df38ad994fc2b463f0aef5111e1279d6dff320548eb7a4f5a9f9eb9421`; the repo copy
  differs only in banner and comment text.
- `scripts/sorcc-target-finalize.sh` was edited 2026-09-01 to require the
  `qwen3/4b-instruct` manifest instead of `llama3.2/3b`. **This edit has not run on
  hardware.** Recompute its hash and re-verify on a bench unit before the next build.

Run `bash -n` after every shell-script edit and recompute the hash before deployment.
