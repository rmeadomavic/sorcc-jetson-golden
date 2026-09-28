#!/usr/bin/env bash
# =============================================================================
# pre-clone-wipe.sh — run on the GOLDEN image right before shutdown + dd.
#
# Idempotent. Safe to re-run. Supports DRY_RUN=1 to preview without changing.
#
# After this runs, the image has:
#   - Neutral hostname (hydra-golden) and no CHIMERA static IP
#   - No adomavic (home) WiFi profile
#   - No Tailscale login, no Claude Code session
#   - Empty machine-id, no SSH host keys  (regenerate per-clone on first boot)
#   - No bash history, no browser cache, no systemd journal
#   - 6.5 GB recovered by dropping dreamshaperXL_lightning
#   - Downloads/, jetson-orin-servo/ removed
#   - Hydra/config.ini reverted (drops stray api_token)
#
# After this script finishes, shut down immediately:  sudo poweroff
# Pull the SD card, dd it to an image, flash that image to student cards,
# and first-boot each clone with:  sudo bash /home/sorcc/student-setup.sh
# =============================================================================

DRY_RUN="${DRY_RUN:-0}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
log()  { printf '%s[wipe]%s %s\n' "$GRN" "$NC" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YEL" "$NC" "$*"; }
err()  { printf '%s[err ]%s %s\n' "$RED" "$NC" "$*" >&2; }

do_or_preview() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '  (dry) %s\n' "$*"
    else
        printf '  %s\n' "$*"
        eval "$@"
    fi
}

if [ "$EUID" -ne 0 ]; then
    err "Must run as root:  sudo bash $0"
    exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
    warn "DRY_RUN=1 — nothing will actually be changed."
else
    cat <<EOF

${YEL}This will reset this Jetson to a neutral golden-image state.${NC}
It will:
  * Log you out of Tailscale (the instructor account)
  * Delete your Claude Code session (~/.claude, ~/.claude.json)
  * Delete the adomavic WiFi profile and CHIMERA static IP
  * Reset hostname to "hydra-golden"
  * Delete the XL checkpoint (if still present)
  * Revert ~/Hydra/config.ini uncommitted changes
  * Clear machine-id, SSH host keys, bash history, browser cache, journal

Run  DRY_RUN=1 sudo bash $0  first if you want to see the plan.

EOF
    read -rp "Continue?  type YES to proceed: " ANSWER
    if [ "$ANSWER" != "YES" ]; then
        err "Aborted."
        exit 1
    fi
fi

# =============================================================================
# A. Disk reclaim
# =============================================================================
log "A. Disk reclaim"

# XL checkpoint (belt-and-braces — should already be gone)
do_or_preview "rm -f /home/sorcc/comfyui/models/checkpoints/dreamshaperXL_lightning.safetensors"

# ComfyUI leftover outputs / test inputs
do_or_preview "find /home/sorcc/comfyui/output -mindepth 1 -delete 2>/dev/null || true"
do_or_preview "find /home/sorcc/comfyui/input  -mindepth 1 -delete 2>/dev/null || true"

# NOTE: /home/sorcc/Downloads and /home/sorcc/jetson-orin-servo are NOT
# removed here. Deal with those manually — see ~/PRE-CLONE-TODO.md.

# Docker cleanup (keeps hydra-detect + comfyui-sorcc tagged; removes dangling
# base tags, stopped containers, and ~1.2 GB of build cache)
do_or_preview "docker container prune -f"
do_or_preview "docker rmi dustynv/comfyui:r36.4.3-cu128-24.04 2>/dev/null || true"
do_or_preview "docker rmi dustynv/l4t-pytorch:r36.4.0 2>/dev/null || true"
do_or_preview "docker image prune -f"
do_or_preview "docker builder prune -af"

# apt cache
do_or_preview "apt-get autoremove -y --purge"
do_or_preview "apt-get clean"

# =============================================================================
# B. Hydra config revert (drops uncommitted api_token + mavlink flip)
# =============================================================================
log "B. Revert Hydra/config.ini"
do_or_preview "sudo -u sorcc git -C /home/sorcc/Hydra checkout -- config.ini"

# =============================================================================
# C. Network identity reset
# =============================================================================
log "C. Network identity"

# Neutral hostname — student-setup.sh overwrites this with hydra-team-N
do_or_preview "hostnamectl set-hostname hydra-golden"
do_or_preview "sed -i 's/127\\.0\\.1\\.1\\s.*/127.0.1.1\\thydra-golden/' /etc/hosts"

# Remove home WiFi profile
do_or_preview "nmcli con delete adomavic 2>/dev/null || true"

# CHIMERA: drop the static IP so the master doesn't come up as 192.168.0.51
# (student-setup.sh re-applies the per-team static IP)
do_or_preview "nmcli con modify CHIMERA ipv4.addresses '' ipv4.method auto 2>/dev/null || true"

# =============================================================================
# D. Accounts logout
# =============================================================================
log "D. Logout Tailscale + Claude Code"

# Tailscale
do_or_preview "tailscale logout 2>/dev/null || true"
do_or_preview "systemctl stop tailscaled"
do_or_preview "rm -rf /var/lib/tailscale/tailscaled.state /var/lib/tailscale/tailscaled.log*.txt /var/lib/tailscale/derpmap.cached.json /var/lib/tailscale/files"

# Defensive: if any authkey was ever written to /etc/default/tailscale for
# testing, remove it so it doesn't ride the clone. student-setup.sh will
# re-prompt each team for their own on first boot.
do_or_preview "rm -f /etc/default/tailscale"

# Claude Code (session, skills, memory, MCP config)
do_or_preview "rm -rf /home/sorcc/.claude /home/sorcc/.claude.json"

# Ollama runs as system service — no per-user auth. Keep the llama3.2:1b model.

# =============================================================================
# E. Clone-sensitive state (do this LAST)
# =============================================================================
log "E. Clone-sensitive state"

# machine-id: truncate (systemd regenerates on first boot of each clone)
do_or_preview "truncate -s 0 /etc/machine-id"
do_or_preview "rm -f /var/lib/dbus/machine-id && ln -sf /etc/machine-id /var/lib/dbus/machine-id"

# SSH host keys: sshd regenerates on next start via ssh.service
do_or_preview "rm -f /etc/ssh/ssh_host_*"

# Bash history
do_or_preview "truncate -s 0 /home/sorcc/.bash_history"
do_or_preview "truncate -s 0 /root/.bash_history 2>/dev/null || true"

# Browser (chromium snap — history, cookies, saved passwords)
do_or_preview "rm -rf /home/sorcc/snap/chromium/common/chromium/Default/History* /home/sorcc/snap/chromium/common/chromium/Default/Cookies* /home/sorcc/snap/chromium/common/chromium/Default/Login*"

# GNOME recently-used files
do_or_preview "rm -f /home/sorcc/.local/share/recently-used.xbel"

# Journal + logs
do_or_preview "journalctl --rotate"
do_or_preview "journalctl --vacuum-time=1s"
do_or_preview "find /var/log -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.old' \\) -delete"

# /tmp
do_or_preview "find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true"
do_or_preview "find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true"

# =============================================================================
# Verify
# =============================================================================
log "F. Post-wipe verification"

check() {
    local label="$1" cmd="$2" expected="$3"
    local actual
    actual="$(eval "$cmd" 2>/dev/null || echo 'ERR')"
    if [ "$actual" = "$expected" ] || [ -z "$expected" ]; then
        printf '  %sok%s  %s\n' "$GRN" "$NC" "$label"
    else
        printf '  %sfail%s %s (got: %s)\n' "$RED" "$NC" "$label" "$actual"
    fi
}

check "machine-id is empty"        "wc -c < /etc/machine-id | tr -d ' '"           "0"
check "no ssh host keys"           "ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l | tr -d ' '" "0"
check "hostname = hydra-golden"    "hostname"                                      "hydra-golden"
check "tailscale logged out"       "tailscale status 2>&1 | grep -c 'Logged out\\|not logged in' | tr -d ' '" ""
check "no ~/.claude"               "[ ! -e /home/sorcc/.claude ] && echo yes"      "yes"
check "no adomavic wifi"           "nmcli con show adomavic 2>/dev/null | wc -l | tr -d ' '" "0"
check "XL checkpoint gone"         "[ ! -f /home/sorcc/comfyui/models/checkpoints/dreamshaperXL_lightning.safetensors ] && echo yes" "yes"
check "config.ini reverted"        "git -C /home/sorcc/Hydra diff --quiet config.ini && echo clean" "clean"

echo
if [ "$DRY_RUN" = "1" ]; then
    warn "Dry run complete. Re-run without DRY_RUN to actually wipe."
else
    cat <<EOF
${GRN}Wipe complete.${NC}

Next steps:
  1. ${YEL}sudo poweroff${NC}
  2. Pull the SD card.
  3. On a workstation with the card reader attached:
       sudo dd if=/dev/sdX of=hydra-golden-2026-04-19.img bs=4M status=progress conv=fsync
       (replace sdX with your reader device — confirm with 'lsblk' first)
  4. Flash that .img onto each student SD card.
  5. On each cloned Jetson, run:
       sudo bash /home/sorcc/student-setup.sh

EOF
fi
