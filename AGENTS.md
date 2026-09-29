# Instructions for AI coding agents (Codex, Claude Code, others)

You are on (or helping with) a Jetson Orin Nano Super that is being set up as a SORCC AI kit.
The goal is a kit that passes the smoke test. The installer does all the work; your job is to
run it, read its output, and fix what it tells you to fix. Do not re-engineer the kit.

## The procedure (same as README.md)

1. Check the platform: `lsb_release -rs; dpkg-query -W -f '${Version}\n' nvidia-l4t-core`.
   Expect `24.04` and `39.x` (JetPack 7.2.1+). Anything else: stop and tell the human. Do not
   try to upgrade or downgrade JetPack with apt; it needs a reflash they must do.
2. `sudo ./install.sh CALLSIGN` (ask the human for the callsign: `HYDRA-1`, `HYDRA-2`, ...).
   Run it from the student's desktop account with sudo, not from a root shell.
3. `sudo reboot`, then with the USB camera plugged in: `sudo /opt/sorcc/sorcc-jetson-smoke-test.sh`.
   Done when it reports `FAIL 0`.

Optional before step 2 on the first kit: `sudo ./scripts/jetpack7-test.sh` (about 30 minutes).

## sudo

These commands need root. If you cannot run `sudo` without a password prompt, do not try to
work around it. Give the human the exact command to run in their own terminal, then read the
result from the log files below.

## When something fails

- The installer and test stop with a message that names the step, the problem, and the fix.
  Do what it says, then run the **same command again**. Finished steps are skipped.
- Logs: `/var/log/sorcc-install.log`, `/var/log/sorcc-jetpack7-test.log`,
  `journalctl -u comfyui -u hydra-detect -u ollama -u sorcc-launcher`.
- `sudo sorcc-diag` bundles everything into a `.tar.gz` for a human to send on.
- Match the symptom to a section of `docs/troubleshooting.md` before inventing a fix.
- Background and Super mode: `docs/jetpack7.md`.

## Do not

- **Do not install, upgrade, or remove Python packages** in `/opt/sorcc/venv` by hand. It is
  built from `jetpack7/requirements.lock` and must match it. To rebuild it:
  `sudo ./install.sh --rebuild CALLSIGN`.
- **Do not use Docker on JetPack 7.** The Docker files in `comfyui/` are the JetPack 6 fallback.
  JetPack 6 containers cannot use the GPU on JetPack 7 (CUDA error 801).
- **Do not change the language model.** It must be `qwen3:4b-instruct`. Never `llama3.2` (the
  license prohibits military use) and never plain `qwen3:4b` (hangs while "thinking").
- **Do not enable features in `hydra/config.ini`.** The class profile is observe-and-report
  only; the switched-off features are checked by the smoke test.
- **Do not skip or weaken checks.** That includes the GPU math check, the SHA-256 download
  checks, and the smoke test. If a check fails, the kit really is broken.
- **Do not run `apt upgrade`/`dist-upgrade`**, flash firmware, or change the power mode config
  beyond what the installer does.
- **Do not use anything in `archive/`.** Those are retired build methods.
- **Do not copy a disk or `/opt/sorcc` from one Jetson to another.** Every kit runs its own
  install so it keeps its own hostname, keys, and Hydra token.
- Do not commit or push to this repo from a kit unless the human asks.

## Needs a human

- Reflashing or reinstalling JetPack (including getting Super mode, see `docs/jetpack7.md`).
- Plugging in the camera, the callsign, the sudo password, and the final desktop check
  (README step 5: wallpaper, desktop shortcut, each tool launches, Stop All).
