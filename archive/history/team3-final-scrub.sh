#!/usr/bin/env bash
# Final privacy and identity scrub for the already-accepted SORCC Team 3 Jetson.
# Intentionally destructive. Review the path lists before running.
set -euo pipefail

MAGIC="${1:-}"
[[ "$MAGIC" == "--execute-sorcc3-scrub" ]] || {
  echo "Refusing to run without --execute-sorcc3-scrub" >&2
  exit 2
}
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }
[[ "$(hostname)" == "sorcc3-desktop" ]] || {
  echo "Wrong host: $(hostname)" >&2
  exit 3
}

TARGET_USER="sorcc3"
TARGET_HOME="/home/$TARGET_USER"
[[ -d "$TARGET_HOME" ]] || { echo "Missing $TARGET_HOME" >&2; exit 3; }
nmcli -t -f NAME connection show | grep -qx CHIMERA || {
  echo "CHIMERA profile missing; refusing to remove remote access state." >&2
  exit 4
}
grep -Eq '^callsign[[:space:]]*=[[:space:]]*HYDRA-3$' /opt/sorcc/hydra/config.ini || {
  echo "Hydra callsign is not HYDRA-3." >&2
  exit 4
}

old_machine_id="$(cat /etc/machine-id)"

# Stop application and remote-overlay activity before removing state.
curl -fsS -X POST http://127.0.0.1:8090/stop >/dev/null 2>&1 || true
systemctl stop ollama comfyui hydra-detect 2>/dev/null || true
if command -v tailscale >/dev/null 2>&1; then
  tailscale logout >/dev/null 2>&1 || true
fi
systemctl disable --now tailscaled 2>/dev/null || true

# Remove the Tailscale client, repository metadata, and node identity.
if dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -q 'install ok installed'; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y tailscale
fi
rm -rf -- \
  /var/lib/tailscale \
  /etc/apt/sources.list.d/tailscale.list \
  /etc/apt/sources.list.d/tailscale.list.save \
  /usr/share/keyrings/tailscale-archive-keyring.gpg

# Remove Claude OAuth/session state, MCP logs, local binary, keyrings, histories,
# transfer credentials, provisioning scratch, and other user-specific traces.
home_paths=(
  "$TARGET_HOME/.claude"
  "$TARGET_HOME/.claude.json"
  "$TARGET_HOME/.cache"
  "$TARGET_HOME/.docker"
  "$TARGET_HOME/.local/share/claude"
  "$TARGET_HOME/.local/state/claude"
  "$TARGET_HOME/.local/bin/claude"
  "$TARGET_HOME/.local/share/applications/claude-code-url-handler.desktop"
  "$TARGET_HOME/.local/share/keyrings"
  "$TARGET_HOME/.local/share/recently-used.xbel"
  "$TARGET_HOME/.local/share/evolution"
  "$TARGET_HOME/.config/evolution"
  "$TARGET_HOME/.config/goa-1.0"
  "$TARGET_HOME/.config/gnome-session/saved-session"
  "$TARGET_HOME/.mozilla"
  "$TARGET_HOME/.config/chromium"
  "$TARGET_HOME/.config/google-chrome"
  "$TARGET_HOME/.config/vivaldi"
  "$TARGET_HOME/snap/chromium"
  "$TARGET_HOME/.ssh"
  "$TARGET_HOME/.bash_history"
  "$TARGET_HOME/.lesshst"
  "$TARGET_HOME/.sudo_as_admin_successful"
  "$TARGET_HOME/ui-pass"
  "$TARGET_HOME/team2-payload-transfer.sh"
  "$TARGET_HOME/team2-comfy-push.sh"
  "$TARGET_HOME/snapd_24724.assert"
  "$TARGET_HOME/snapd_24724.snap"
)
rm -rf -- "${home_paths[@]}"

system_paths=(
  /var/tmp/sorcc-team2-comfy-push.log
  /var/tmp/sorcc-team2-comfy-push.ok
  /var/tmp/sorcc-team2-transfer.log
  /etc/systemd/system/sorcc-team2-transfer.service
  /etc/systemd/system/multi-user.target.wants/sorcc-team2-transfer.service
  /var/log/journal
)
rm -rf -- "${system_paths[@]}"

# Restore a stock shell and empty per-user state directories.
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0644 /etc/skel/.bashrc "$TARGET_HOME/.bashrc"
install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
  "$TARGET_HOME/.cache" "$TARGET_HOME/.ssh" "$TARGET_HOME/.local/share/keyrings"

# Replace the stale Claude URL-handler default with a clean Chromium launcher.
rm -f "$TARGET_HOME/.config/mimeapps.list"
install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
  "$TARGET_HOME/.config" "$TARGET_HOME/.local/share/applications"
cat >"$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Chromium Web Browser
Exec=/snap/bin/chromium --no-first-run --no-default-browser-check %U
Terminal=false
Icon=chromium
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
NoDisplay=true
EOF
cat >"$TARGET_HOME/.config/mimeapps.list" <<'EOF'
[Default Applications]
text/html=sorcc-chromium.desktop
x-scheme-handler/http=sorcc-chromium.desktop
x-scheme-handler/https=sorcc-chromium.desktop
EOF
chown "$TARGET_USER:$TARGET_USER" \
  "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" \
  "$TARGET_HOME/.config/mimeapps.list"
chmod 0644 \
  "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" \
  "$TARGET_HOME/.config/mimeapps.list"

# Clear text login/package logs that can retain names, IPs, and command history.
for pattern in \
  '/var/log/auth.log*' '/var/log/syslog*' '/var/log/kern.log*' \
  '/var/log/user.log*' '/var/log/wtmp*' '/var/log/btmp*' \
  '/var/log/lastlog' '/var/log/dpkg.log*'; do
  for log in $pattern; do
    [[ -f "$log" ]] && truncate -s 0 "$log"
  done
done
find /var/log/apt -maxdepth 1 -type f -exec truncate -s 0 {} + 2>/dev/null || true

# Rotate the machine identity and every SSH host key.
rm -f /etc/machine-id /var/lib/dbus/machine-id
new_machine_id="$(tr -d '-' </proc/sys/kernel/random/uuid)"
printf '%s\n' "$new_machine_id" >/etc/machine-id
chmod 0444 /etc/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

new_machine_id="$(cat /etc/machine-id)"
[[ -n "$new_machine_id" && "$new_machine_id" != "$old_machine_id" ]] || {
  echo "Machine ID did not rotate." >&2
  exit 5
}

systemctl daemon-reload
systemctl restart systemd-journald

# Pre-reboot privacy assertions. Do not print any token or credential content.
for path in "${home_paths[@]}" "${system_paths[@]}" /var/lib/tailscale; do
  case "$path" in
    "$TARGET_HOME/.cache"|"$TARGET_HOME/.ssh"|"$TARGET_HOME/.local/share/keyrings")
      [[ -d "$path" ]] || { echo "Expected empty directory missing: $path" >&2; exit 6; }
      [[ -z "$(find "$path" -mindepth 1 -print -quit)" ]] || {
        echo "Scrub residue: $path" >&2
        exit 6
      }
      ;;
    *)
      [[ ! -e "$path" ]] || { echo "Scrub residue: $path" >&2; exit 6; }
      ;;
  esac
done
hash -r
for path in /usr/bin/tailscale /usr/local/bin/tailscale; do
  [[ ! -e "$path" ]] || { echo "Tailscale binary remains: $path" >&2; exit 6; }
done
if dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -q 'install ok installed'; then
  echo "Tailscale package remains." >&2
  exit 6
fi
[[ "$(find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*_key' | wc -l)" -ge 3 ]] || {
  echo "SSH host-key regeneration failed." >&2
  exit 6
}
nmcli -t -f NAME connection show | grep -qx CHIMERA
grep -Eq '^callsign[[:space:]]*=[[:space:]]*HYDRA-3$' /opt/sorcc/hydra/config.ini

printf 'SCRUB_OK host=%s machine_id_sha256=%s ssh_ed25519=%s\n' \
  "$(hostname)" \
  "$(printf %s "$new_machine_id" | sha256sum | cut -d' ' -f1)" \
  "$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"

sync
systemctl reboot
