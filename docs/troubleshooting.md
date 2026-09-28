# Troubleshooting

Start here when the installer stops, the smoke test fails, or a tool will not open.

To send someone the full picture, run `sudo sorcc-diag` and share the
`/tmp/sorcc-diag-*.tar.gz` file it prints. It masks the Hydra token.

## The installer stopped

The last lines say which step stopped and why. Fix that, then run the same command again
(`sudo ./install.sh HYDRA-N`). Finished work is skipped: images already downloaded and
models already checked are not fetched again. The full log is `/var/log/sorcc-install.log`.

Network errors (timeouts, "connection reset") usually pass on a second run.

## The JetPack 7 test says "use the JetPack 6 backup"

Look at which line failed in the result table (the full output is in
`/var/log/sorcc-jetpack7-test.log`):

- **gpu FAIL** or **imagery FAIL: the image came out blank**: the GPU gives wrong results on
  this JetPack 7 install. Reflash with JetPack 6.2.x: [reflash-jetpack6-nvme.md](reflash-jetpack6-nvme.md).
- **imagery FAIL: ComfyUI did not start**: read the end of
  `/opt/sorcc/jetpack7-test-comfyui.log`. Out-of-memory or a missing package is worth one
  re-run of the test after a reboot. If it fails again, use JetPack 6.
- A **download** or **network** error stops the test before the table. Re-run it; finished
  downloads are reused.

## "The GPU check failed on JetPack 7"

The installer stops here when PyTorch cannot see the GPU or computes wrong results. First
reboot and run the installer again. If it still fails, run `sudo ./scripts/jetpack7-test.sh`
for a fuller report, and plan on the JetPack 6 backup.

## "Not enough free disk space"

The kit needs about 55 GB free on a fresh install. Use a 256 GB or larger NVMe drive. To see
what is using space: `sudo du -xh --max-depth=2 / | sort -h | tail -20`.

## "Downloaded file is damaged or has changed upstream"

The installer deleted the bad file. Run it again. If the same file fails twice, the file on
Hugging Face has changed; report it so `comfyui/models.txt` can be updated.

## "A test container could not use the GPU" (JetPack 6)

Docker is installed, but containers cannot reach the GPU. In order:

1. Confirm JetPack 6: `head -1 /etc/nv_tegra_release` must start with `# R36`.
2. Install the full JetPack component set, then reboot:
   ```bash
   sudo apt update && sudo apt install -y nvidia-jetpack
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo reboot
   ```
3. Run the installer again.

## Chromium will not install or start

A snapd update once broke Chromium on these Jetsons. The installer holds snapd after it
installs Chromium so it cannot update itself. If Chromium still fails, install the known-good
snapd revision, hold it, and reinstall Chromium:

```bash
snap download snapd --revision=24724
sudo snap ack snapd_24724.assert
sudo snap install snapd_24724.snap
sudo snap refresh --hold snapd
sudo snap remove chromium && sudo snap install chromium
```

Then run the installer again.

## "MAXN_SUPER is not available"

The board was installed without the Super configuration, so the GPU runs slower. Everything
still works. On JetPack 7, see "Super mode" in [jetpack7.md](jetpack7.md) (the JetPack 7.2 USB
installer causes this). On JetPack 6, reflash using SDK Manager or the
`jetson-orin-nano-devkit-super` command in [reflash-jetpack6-nvme.md](reflash-jetpack6-nvme.md).

## An NVIDIA "reboot required" notice keeps coming back

This happens on kits upgraded with `apt` when the board firmware (QSPI) is older than the
system. Check with `sudo nvbootctrl dump-slots-info`. Update the firmware with NVIDIA's capsule
helper, rebooting after each run, until both slots report the same version as
`/etc/nv_tegra_release`:

```bash
sudo nv_bootloader_capsule_updater.sh -q /opt/ota_package/t23x/TEGRA_BL_3767_super.Cap
sudo reboot
```

A kit flashed with the reflash guide does not need this.

## A Launch button says "Did not start. Try again"

The tool's service failed. See why:

```bash
journalctl -u hydra-detect -n 50 --no-pager    # Detection
journalctl -u comfyui -n 50 --no-pager         # Imagery
journalctl -u ollama -n 50 --no-pager          # Language
```

Common causes:

- **Detection:** no camera. Check `ls /dev/video*`, replug the camera, then select Launch again.
- **Imagery:** out of memory after heavy use. Select **Stop All**, then Launch again. Reboot
  if it still fails.
- **Any tool:** the image or model is missing. Run the installer again.

## Imagery: "CUDA out of memory" or very slow

Keep the resolution at 256 x 256 and the batch size at 1. Close extra browser tabs. From the
launcher, select **Stop All** and start Imagery again. That restarts ComfyUI and
compacts memory.

## Language is slow

That is by design. The model runs on the CPU so the 8 GB of shared memory stays free for the
other tools. Expect a few words per second. The first answer after launch also loads the model.

## Smoke test failures

| Section | What to check |
|---|---|
| 1. Base platform | JetPack 7 or 6.2.x, `sudo nvpmodel -q` shows MAXN, camera plugged in, installer finished |
| 2. Hydra dark surface | Someone edited `/opt/sorcc/hydra/config.ini`; run the installer again to restore it |
| 3. Detection | Camera plugged in; `journalctl -u hydra-detect` |
| 4. Language | `journalctl -u ollama`; `ollama list` must show `qwen3:4b-instruct` |
| 5. Imagery | `journalctl -u comfyui`; `ls /opt/sorcc/comfyui/models/*` |
| 6. Stop All | `systemctl --failed` |

## Rebuild or reset pieces

| To do this | Run |
|---|---|
| Rebuild the ComfyUI image (JetPack 6) or the Python environment (JetPack 7) | `sudo ./install.sh --rebuild HYDRA-N` |
| Change the kit's callsign | `sudo ./install.sh HYDRA-N` with the new callsign |
| Make a new Hydra token | `sudo rm /opt/sorcc/hydra/config.ini`, then run the installer |
| Restore the class Hydra config | Run the installer (it rewrites the config and keeps the token) |
