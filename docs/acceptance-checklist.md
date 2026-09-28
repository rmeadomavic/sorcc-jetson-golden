# Acceptance and hand-off checklist

Run through this for each kit after `install.sh` finishes and the kit has rebooted. Kits
are issued to students and leave with them, so check each one.

## 1. Software acceptance

With the USB camera connected:

```bash
sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
```

Pass: `PASS 24  WARN 1  FAIL 0`, or `PASS 25` with a person in front of the camera. The test
drives the kit the way a student does and checks real outputs, not just the absence of errors:

- JetPack 7 native build (or the 6.2.x Docker fallback), MAXN power mode, camera, model files, desktop shortcut
- Hydra's switched-off features are still off
- Detection: live camera frame, detector running, FPS reported
- Language: a real streamed answer with token and timing metrics
- Imagery: ComfyUI 0.19.3 with the class flags, a real PNG from the START HERE workflow, and
  the workflows published
- One tool at a time in all three modes, and Stop All leaves nothing running or failed

## 2. Desktop acceptance (required, even after a clean smoke test)

A shortcut file can exist without a browser that can open it; the smoke test cannot see that.

1. Log in at the physical desktop.
2. Wallpaper: the SORCC AI KIT title centered on black.
3. Double-click **SORCC AI Kit**. (First time: right-click, **Allow Launching**.)
4. Chromium opens the launcher directly with no first-run, sign-in, sync, or default-browser
   prompt.
5. The launcher shows Language, Imagery, Detection, the RAM/GPU/temperature bar, and Stop All.
6. **Language:** both Enter and Send submit a prompt. The stage indicators and the finish
   metrics update.
7. **Imagery:** the START HERE workflow opens by itself with the 256-pixel, 4-step LCM preset.
   Select **Run** and get an image.
8. **Detection:** the real camera image with boxes. Put a person in frame and confirm the box,
   the label, and a track ID that stays stable.
9. **Stop All** releases the memory and the camera; the launcher itself stays up.

Write down what you actually saw. A healthy view of the ceiling is a camera check, not a
tracking test.

## 3. Privacy and identity

Each kit keeps its own hostname, Linux account, machine ID, SSH host keys, and Hydra token.
Before issue, confirm nothing from an instructor or another machine is left on it:

```bash
find "$HOME" -maxdepth 3 \( -name '.claude*' -o -name '.codex*' -o -iname '*tailscale*' \) -print
dpkg-query -W tailscale 2>/dev/null || true
ls -la ~/.ssh 2>/dev/null
```

- No Claude, Codex, or Tailscale state
- No SSH keys except an instructor public key that current policy explicitly approves
- Chromium: no signed-in account, saved passwords, or non-local history
- The repo folder (`~/sorcc-jetson-golden`) can stay or go. It holds nothing secret.

## 4. Final gate

| Gate | Required result |
|---|---|
| Firmware | JetPack 7.2.1+ (or the 6.2.x fallback), the same on every kit in the class; no pending reboot notice |
| Power | MAXN_SUPER; GPU maximum 1020 MHz (`cat /sys/devices/platform/*gpu*/devfreq/*/max_freq` shows `1020000000`) |
| Services | launcher running (and Docker, on JetPack 6); `systemctl --failed` empty; the three tools start only on demand |
| Privacy | section 3 clean |
| Identity | unique host, account, callsign, and Hydra token |
| Browser | the desktop shortcut opens a clean local Chromium |
| Language | streamed answer; Enter and Send both work |
| Imagery | a real 256 x 256 PNG from START HERE in roughly 40 to 60 seconds |
| Detection | live C270 image at roughly 30 to 39 FPS |
| Controls | one tool at a time; Stop All works |

Do not issue a kit until every gate passes, or the course lead accepts what is left.

## 5. Shut down cleanly

```bash
sudo systemctl poweroff
```

Wait for the board to finish shutting down before you pull power.

## Known-good numbers (2026-07 build, JetPack 6.2, microSD; JetPack 7 numbers still to be recorded)

- Detection: 34 to 38 FPS, 23 to 26 ms inference
- Imagery START HERE: 46 to 50 seconds for the first image
- Smoke test: 24 passes, 1 manual warning, 0 failures

NVMe loads faster than microSD. It does not change the 256-pixel limit for ComfyUI, which
comes from memory, not storage.
