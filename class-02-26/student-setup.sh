#!/bin/bash
# =============================================================================
# SORCC Class 02-26 — Jetson Orin Nano Super First-Boot Setup
# Run once per cloned Jetson: sudo bash /home/sorcc/student-setup.sh
# Idempotent — safe to re-run if something fails partway through.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo bash $0)"
    exit 1
fi

SORCC_USER="sorcc"
SORCC_HOME="/home/${SORCC_USER}"

# ─── Prompt for team number ─────────────────────────────────────────────────
while true; do
    read -rp "Enter TEAM NUMBER (1-5): " TEAM_NUM
    if [[ "$TEAM_NUM" =~ ^[1-5]$ ]]; then
        break
    fi
    err "Invalid input. Enter a number from 1 to 5."
done

HOSTNAME="hydra-team-${TEAM_NUM}"
STATIC_IP="192.168.0.$((50 + TEAM_NUM))"

log "Team ${TEAM_NUM}: hostname=${HOSTNAME}, IP=${STATIC_IP}"

# ─── A. Set hostname ────────────────────────────────────────────────────────
log "Setting hostname to ${HOSTNAME}..."
hostnamectl set-hostname "${HOSTNAME}"
# Update /etc/hosts
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
else
    echo "127.0.1.1	${HOSTNAME}" >> /etc/hosts
fi

# ─── B. Set static IP on CHIMERA WiFi ───────────────────────────────────────
log "Configuring static IP ${STATIC_IP} on CHIMERA..."
CHIMERA_CONN=$(nmcli -t -f NAME connection show | grep -i "CHIMERA" | head -1)
if [[ -z "$CHIMERA_CONN" ]]; then
    warn "CHIMERA WiFi connection not found. You'll need to connect manually first."
    warn "After connecting, re-run this script to set the static IP."
else
    nmcli connection modify "${CHIMERA_CONN}" \
        ipv4.method manual \
        ipv4.addresses "${STATIC_IP}/24" \
        ipv4.gateway "192.168.0.1" \
        ipv4.dns "8.8.8.8" \
        connection.autoconnect yes
    nmcli connection up "${CHIMERA_CONN}" 2>/dev/null || \
        warn "Could not activate CHIMERA right now — will apply on next connect."
    log "Static IP configured: ${STATIC_IP}"
fi

# ─── B.5 Disable WiFi powersave (rtl8822ce stability) ───────────────────────
# The Realtek rtl8822ce in the Orin Nano drops association every few seconds
# when NetworkManager's default powersave is on (wifi.powersave = 3). Force
# it off so the Jetson stays connected under idle.
log "Disabling WiFi powersave (rtl8822ce fix)..."
cat > /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
systemctl restart NetworkManager

# ─── B.6 Apply OS hardening (journald, docker, swap, udev, sorcc-diag) ──────
# See /home/sorcc/jetson-hardening/apply-hardening.sh for details. Reversible.
log "Applying Jetson OS hardening..."
HARDENING_DIR="${SORCC_HOME}/jetson-hardening"
if [[ -d "${HARDENING_DIR}" ]]; then
    apt-get update -qq
    bash "${HARDENING_DIR}/apply-hardening.sh"
else
    warn "jetson-hardening/ not found at ${HARDENING_DIR} — skipping hardening"
fi

# ─── C. Clone or update Hydra repo ──────────────────────────────────────────
HYDRA_DIR="${SORCC_HOME}/Hydra"
log "Setting up Hydra repository..."
if [[ -d "${HYDRA_DIR}/.git" ]]; then
    log "Hydra repo exists — pulling latest..."
    sudo -u "${SORCC_USER}" git -C "${HYDRA_DIR}" pull
else
    log "Cloning Hydra repo..."
    if ! sudo -u "${SORCC_USER}" git clone https://github.com/rmeadomavic/Hydra.git "${HYDRA_DIR}"; then
        err "Failed to clone Hydra repo. Is it public? Check https://github.com/rmeadomavic/Hydra"
        err "If the repo is private, make it public or configure git credentials first."
        exit 1
    fi
fi

# ─── D. Install Hydra dependencies (Jetson-safe) ────────────────────────────
# NOTE: Hydra runs in Docker for production (CUDA acceleration).
# These bare-metal deps are for development/testing only.
# We use --no-deps for ultralytics/supervision to avoid pulling redundant
# NVIDIA CUDA pip wheels that conflict with JetPack's native CUDA.
log "Installing Hydra Python dependencies (Jetson-safe)..."
if [[ -f "${HYDRA_DIR}/requirements.txt" ]]; then
    pip3 install --no-deps ultralytics supervision
    grep -v "opencv-python\|ultralytics\|supervision" "${HYDRA_DIR}/requirements.txt" > /tmp/hydra-reqs.txt
    pip3 install -r /tmp/hydra-reqs.txt
    pip3 install opencv-python-headless
    rm -f /tmp/hydra-reqs.txt
else
    warn "No requirements.txt found in Hydra repo — skipping pip install."
fi

# ─── E. Install Docker ──────────────────────────────────────────────────────
log "Checking Docker installation..."
if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
else
    log "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq docker.io
    systemctl enable --now docker
fi

# Add sorcc to docker group
if id -nG "${SORCC_USER}" | grep -qw docker; then
    log "User ${SORCC_USER} already in docker group."
else
    usermod -aG docker "${SORCC_USER}"
    log "Added ${SORCC_USER} to docker group (re-login required for effect)."
fi

# Add sorcc to dialout group (needed for serial/MAVLink)
if id -nG "${SORCC_USER}" | grep -qw dialout; then
    log "User ${SORCC_USER} already in dialout group."
else
    usermod -aG dialout "${SORCC_USER}"
    log "Added ${SORCC_USER} to dialout group (re-login required for effect)."
fi

# ─── E.5 Kismet + RTL-SDR stack (for RF homing / counter-UAS training) ──────
# Adds the official Kismet apt repo (Kismet is NOT in Ubuntu's archive),
# installs Kismet + rtl-sdr, generates a per-Jetson HTTP API password,
# renders /etc/kismet/kismet_site.conf, installs the systemd unit, and
# mirrors the password into Hydra's config.ini so the RF hunt controller
# and ambient scan poller both authenticate on first boot.
log "Installing Kismet + RTL-SDR for RF homing..."

if [ ! -f /etc/apt/keyrings/kismet.gpg ]; then
    log "Adding Kismet apt repo..."
    mkdir -p /etc/apt/keyrings
    wget -qO- https://www.kismetwireless.net/repos/kismet-release.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/kismet.gpg
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-jammy}"
    echo "deb [signed-by=/etc/apt/keyrings/kismet.gpg] https://www.kismetwireless.net/repos/apt/release/${CODENAME} ${CODENAME} main" \
        > /etc/apt/sources.list.d/kismet.list
    apt-get update -qq
fi

# Pre-answer Kismet debconf questions (avoid interactive setuid prompt).
echo "kismet-core kismet-core/install-users boolean true" | debconf-set-selections
echo "kismet-core kismet-core/install-setuid boolean true" | debconf-set-selections

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    kismet rtl-sdr librtlsdr0 rtl-433 2>&1 | tail -3 || \
    warn "Kismet/RTL-SDR install had non-zero exit — inspect apt log"
# rtl-433 is the binary that kismet-capture-rtl433-v2 shells out to. Kismet
# claims to "launch successfully" without it, but then immediately errors
# with "could not find rtl_433 binary in path." Keep it in the install list.

# Ensure sorcc in kismet group (plugdev handled by hardening).
if ! id -nG "${SORCC_USER}" | grep -qw kismet; then
    usermod -aG kismet "${SORCC_USER}"
    log "Added ${SORCC_USER} to kismet group (re-login for effect)"
fi

# Per-Jetson Kismet HTTP password. Source of truth is ${PW_FILE}: if
# it's missing or empty (fresh SD-card clone — the file is stripped
# before imaging) we mint a new one. If it has content we trust it and
# reuse. kismet_site.conf is always (re)rendered from PW_FILE so a
# hand-edit or stale password doesn't silently drift.
KISMET_CONF=/etc/kismet/kismet_site.conf
PW_FILE="${SORCC_HOME}/.kismet_pw"
mkdir -p /etc/kismet /var/log/kismet
if [ ! -s "${PW_FILE}" ]; then
    KISMET_PW=$(openssl rand -hex 16)
    printf "%s" "${KISMET_PW}" > "${PW_FILE}"
    chown "${SORCC_USER}:${SORCC_USER}" "${PW_FILE}"
    chmod 0600 "${PW_FILE}"
    log "Generated fresh Kismet password for this Jetson (${PW_FILE})"
else
    KISMET_PW=$(cat "${PW_FILE}")
    log "Reusing existing Kismet password from ${PW_FILE}"
fi
cat > "${KISMET_CONF}" <<EOF
# SORCC Hydra — Kismet site config (rendered by student-setup.sh)
# RTL-SDR @ 433.92 MHz: weather sensors, car fobs, ISM telemetry.
# Note: built-in hci0 via kismet-capture-linux-bluetooth is intentionally
# NOT a source here — that driver is tuning_capable=0 / hop_capable=0
# and does not report per-advertisement RSSI, so it would contribute
# device MACs without real RF data. For true BLE capture, add an
# Ubertooth One (type=ubertooth) when hardware is available.
source=rtl433-0:type=rtl433,name=NESDR
httpd_username=kismet
httpd_password=${KISMET_PW}
httpd_bind_address=127.0.0.1
httpd_port=2501
log_prefix=/var/log/kismet/
log_types=kismet
allowed_auth_ips=127.0.0.1,::1
EOF
chmod 0640 "${KISMET_CONF}"
chown root:kismet "${KISMET_CONF}" 2>/dev/null || true

# Install Kismet systemd unit from the Hydra repo.
KISMET_UNIT="${HYDRA_DIR}/scripts/kismet.service"
if [ -f "${KISMET_UNIT}" ]; then
    install -D -m 0644 "${KISMET_UNIT}" /etc/systemd/system/kismet.service
    systemctl daemon-reload
    systemctl enable kismet.service >/dev/null 2>&1
    log "Kismet systemd unit installed + enabled (starts at next boot)"
else
    warn "${KISMET_UNIT} not found — RF homing will not auto-start"
fi

# Mirror Kismet credentials into Hydra's config.ini.
HYDRA_CONFIG="${HYDRA_DIR}/config.ini"
if [ -f "${HYDRA_CONFIG}" ] && [ -s "${PW_FILE}" ]; then
    KISMET_PW=$(cat "${PW_FILE}")
    # Append [kismet] block if absent (ambient scan poller config).
    if ! grep -q "^\[kismet\]" "${HYDRA_CONFIG}"; then
        cat >> "${HYDRA_CONFIG}" <<EOF

[kismet]
enabled = true
host = http://127.0.0.1:2501
user = kismet
password = ${KISMET_PW}
source = rtl433-0
poll_interval_sec = 0.5
timeout_sec = 2.0
max_samples_per_cycle = 50
EOF
        log "Appended [kismet] section to ${HYDRA_CONFIG}"
    fi
    # Refresh credentials inside the pre-existing [rf_homing] section.
    # Match any current value (placeholder or stale) so re-runs after a
    # password regeneration don't leave the file out of sync. The
    # kismet_pass key only appears under [rf_homing] in the committed
    # config.ini, so a global sed is safe.
    sed -i -E "s|^kismet_pass = .*$|kismet_pass = ${KISMET_PW}|" "${HYDRA_CONFIG}"
    sed -i -E "s|^kismet_host = http://(localhost\|127\.0\.0\.1):2501$|kismet_host = http://127.0.0.1:2501|" "${HYDRA_CONFIG}"
fi

# ─── F. Install Ollama ──────────────────────────────────────────────────────
log "Checking Ollama installation..."
if command -v ollama &>/dev/null; then
    log "Ollama already installed: $(ollama --version 2>/dev/null || echo 'installed')"
else
    log "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    sh /tmp/ollama-install.sh
    rm -f /tmp/ollama-install.sh
fi

log "Pulling default model (llama3.2:1b)..."
ollama pull llama3.2:1b || warn "Could not pull model — you can retry with: ollama pull llama3.2:1b"

# ─── G. Install Tailscale ───────────────────────────────────────────────────
log "Checking Tailscale installation..."
if command -v tailscale &>/dev/null; then
    log "Tailscale already installed."
else
    log "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
    sh /tmp/tailscale-install.sh
    rm -f /tmp/tailscale-install.sh
fi

# ─── G.5 Tailscale auto-join (optional, per team's choice) ──────────────────
# Each team decides their own Tailscale setup — reuse their existing account,
# create a new one, or skip. If the team has a reusable authkey from their
# Tailscale admin console, paste it here and this Jetson will auto-join the
# tailnet on every boot. Otherwise leave blank and run 'sudo tailscale up'
# manually to do the standard browser auth.
echo ""
echo -e "${YELLOW}Tailscale (optional):${NC} paste a reusable authkey to auto-join the tailnet,"
echo -e "${YELLOW}or leave blank to set up manually later via 'sudo tailscale up'.${NC}"
if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
    read -rp "Authkey (tskey-auth-...) or blank to skip: " TAILSCALE_AUTHKEY || true
fi
if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    log "Configuring Tailscale auto-join..."
    umask 077
    printf 'TAILSCALE_AUTHKEY=%s\n' "${TAILSCALE_AUTHKEY}" > /etc/default/tailscale
    chmod 600 /etc/default/tailscale
    systemctl enable --now tailscale-autojoin.service 2>/dev/null || \
        warn "tailscale-autojoin.service failed — check 'journalctl -u tailscale-autojoin'"
else
    echo ""
    echo -e "${YELLOW}  Tailscale not auto-joined. Run 'sudo tailscale up' manually.${NC}"
    echo ""
fi

# ─── H. Enable SSH ──────────────────────────────────────────────────────────
log "Enabling SSH..."
apt-get install -y -qq openssh-server 2>/dev/null || true
# Regenerate host keys if missing (e.g. after SD card clone)
if ! ls /etc/ssh/ssh_host_*_key &>/dev/null; then
    log "Regenerating SSH host keys (first boot after clone)..."
    dpkg-reconfigure openssh-server
fi
systemctl enable ssh
systemctl restart ssh
log "SSH enabled and running."

# ─── I. Set up Avahi/mDNS ───────────────────────────────────────────────────
log "Setting up Avahi/mDNS for ${HOSTNAME}.local..."
apt-get install -y -qq avahi-daemon 2>/dev/null || true
systemctl enable --now avahi-daemon
log "Jetson will be discoverable as ${HOSTNAME}.local"

# ─── J. Regenerate machine-id (for fresh clone identity) ────────────────────
log "Regenerating /etc/machine-id..."
rm -f /etc/machine-id
systemd-machine-id-setup

# ─── J.1 Clear stale Chromium snap profile lock from golden image ───────────
# SingletonLock symlinks to <hostname>-<pid>; if the hostname doesn't match
# the box currently running, snap's chromium refuses to launch silently.
CHROMIUM_PROFILE="/home/sorcc/snap/chromium/common/chromium"
if [ -d "${CHROMIUM_PROFILE}" ]; then
    log "Clearing stale Chromium singleton lock from golden image..."
    rm -f "${CHROMIUM_PROFILE}/SingletonLock" \
          "${CHROMIUM_PROFILE}/SingletonCookie" \
          "${CHROMIUM_PROFILE}/SingletonSocket"
fi

# ─── K. Point to Hydra's own setup for Docker build + hardware config ───────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  SORCC Class 02-26 — Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Hostname:        $(hostname)"
echo "  Static IP:       ${STATIC_IP} (on CHIMERA)"
echo "  Hydra path:      ${HYDRA_DIR}"
echo "  Docker:          $(docker --version 2>/dev/null || echo 'not found')"
echo "  Ollama:          $(ollama --version 2>/dev/null || echo 'installed')"
echo "  Tailscale:       $(tailscale status 2>/dev/null || echo 'installed, not authenticated')"
echo "  SSH:             $(systemctl is-active ssh)"
echo "  mDNS:            ${HOSTNAME}.local"
echo ""
echo -e "${YELLOW}  Next steps:${NC}"
echo "    1. Run 'sudo tailscale up' to authenticate Tailscale"
echo "    2. Run 'bash ${HYDRA_DIR}/scripts/hydra-setup.sh' to build Docker + configure hardware"
echo "    3. Reboot to apply hostname changes"
echo ""
