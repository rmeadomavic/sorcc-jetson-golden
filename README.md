# SORCC AI Kit — Jetson Setup

Three student Jetson kits (Team 1, 2, 3). Each runs Language (Ollama), Imagery
(ComfyUI), and Detection (Hydra) behind one launcher page, one tool at a time.
Students double-click the desktop shortcut; everything else is already installed.

## Before the course: check the existing kits

The three kits are built and accepted. For each one:

1. Power on, connect the USB camera, and log in. The password is the classroom
   default printed on the kit card.
2. Run the acceptance test:

   ```bash
   sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
   ```

   Expect 24 passes, 0 failures. One warning appears if the camera sees no
   recognizable object; put a person in frame and re-run to clear it.
3. Double-click **SORCC AI Kit** on the desktop and walk through the checks in
   runbook step 9: all three tools respond, the browser opens clean, Stop All
   releases RAM and the camera.

If all three kits pass, you are done. Issue them.

## If a kit is broken or you need a new one

Follow `docs/provisioning-runbook.md` top to bottom; it has every command. The
sequence:

1. Confirm you are on the right physical Jetson (hostname, user, host key).
2. Update to JetPack 6.2.2 / L4T 36.4.7 and bring both QSPI firmware slots to
   36.4.7. QSPI is per-board; no image carries it. (Runbook step 3.)
3. Install Chromium (snap).
4. Copy the application payload from a working kit to `~/sorcc-stage/` over the LAN,
   and load the two Docker images. Runbook step 5 lists the exact tree and image pins.
5. Copy `scripts/sorcc-target-finalize.sh` from this repo to the target and run it:

   ```bash
   sudo ./sorcc-target-finalize.sh "$(id -un)" HYDRA-N
   ```

   `N` is the team number. The script checks its own prerequisites and stops if
   anything is missing. Note: this copy was updated for the qwen model swap and has
   not been re-run on hardware yet; see the hash note at the end of the runbook.
6. Run the acceptance test and the desktop check from the section above.
7. Delete `~/sorcc-stage/`, remove transfer keys, and finish the cleanup checklist
   in runbook step 10.

## Rules that matter

- The LLM is `qwen3:4b-instruct`. Never `llama3.2:3b` (Meta license prohibits military
  use) and never plain `qwen3:4b` (thinking model, hangs instead of answering).
- One heavy tool at a time. 8 GB is not enough for two. The launcher enforces this;
  do not disable it.
- Keep ComfyUI images at 256 x 256. Bigger runs out of memory.
- Never `dd`-clone a kit's SD card to another kit. It copies the machine's identity and
  credentials. That is why the `legacy-clone-method/` folder is retired.

## More detail

- `docs/provisioning-runbook.md` — the full procedure with every command and gate
- `docs/class-image-spec.md` — what students may touch and what stays disabled
- `scripts/` — the installer, acceptance test, launcher, and student workflows
- Hydra source: <https://github.com/rmeadomavic/Hydra>
