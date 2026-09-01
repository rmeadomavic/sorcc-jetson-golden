#!/bin/bash
# apply-hardening.sh — idempotent application of SORCC Jetson OS hardening.
# Run by /home/sorcc/student-setup.sh, or manually: sudo bash apply-hardening.sh
# Safe to re-run — each step is guarded.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "apply-hardening.sh must run as root" >&2
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[HARDEN]${NC} $*"; }
warn() { echo -e "${YELLOW}[HARDEN]${NC} $*"; }

# A1. Persistent journal + size cap
log "journald: persistent storage + 200M cap"
install -D -m 0644 "${HERE}/journald-10-sorcc.conf" \
    /etc/systemd/journald.conf.d/10-sorcc.conf
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
systemctl restart systemd-journald

# A2. Docker log rotation + live-restore
log "docker: live-restore + 50M x 3 log rotation"
install -D -m 0644 "${HERE}/docker-daemon.json" /etc/docker/daemon.json
systemctl restart docker

# A3. 4 GB disk swap (supplementing zram)
if [[ ! -f /swapfile ]]; then
    log "swap: creating /swapfile (4G)"
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    if ! grep -q '^/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw,pri=1 0 0' >> /etc/fstab
    fi
else
    log "swap: /swapfile already present"
    swapon /swapfile 2>/dev/null || true
fi

# A4. Mask unattended-upgrades + apt daily timers
log "apt: masking unattended-upgrades and apt-daily timers"
systemctl mask --now unattended-upgrades.service >/dev/null 2>&1 || true
systemctl mask --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

# A5. btop + v4l-utils
log "apt: installing btop + v4l-utils"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq btop v4l-utils >/dev/null

# A6. USB udev rules for RTL-SDR and Pixhawk
log "udev: installing 99-sorcc-hydra.rules"
install -D -m 0644 "${HERE}/99-sorcc-hydra.rules" /etc/udev/rules.d/99-sorcc-hydra.rules
udevadm control --reload
udevadm trigger
# Ensure sorcc is in plugdev (for SDR)
if id -u sorcc >/dev/null 2>&1 && ! id -nG sorcc | grep -qw plugdev; then
    usermod -aG plugdev sorcc
    log "added sorcc to plugdev (re-login for effect)"
fi

# A6.1 Blacklist kernel DVB-T driver so librtlsdr can claim the dongle.
# Without this, dvb_usb_rtl28xxu autoloads on plug-in and holds the device
# exclusively — rtl_test/rtl_power/Kismet's rtl433 source all fail.
log "udev: blacklisting dvb_usb_rtl28xxu kernel module"
BLFILE=/etc/modprobe.d/blacklist-rtlsdr.conf
if ! grep -q "dvb_usb_rtl28xxu" "${BLFILE}" 2>/dev/null; then
    echo "blacklist dvb_usb_rtl28xxu" > "${BLFILE}"
    log "wrote ${BLFILE}"
fi
# Unload now if currently loaded; harmless if not.
rmmod dvb_usb_rtl28xxu 2>/dev/null || true

# A7. sorcc-diag
log "installing /usr/local/bin/sorcc-diag"
install -D -m 0755 "${HERE}/sorcc-diag" /usr/local/bin/sorcc-diag

# A9. Tailscale auto-join service unit (authkey file provisioned separately)
log "installing tailscale-autojoin.service"
install -D -m 0644 "${HERE}/tailscale-autojoin.service" \
    /etc/systemd/system/tailscale-autojoin.service
systemctl daemon-reload
systemctl enable tailscale-autojoin.service >/dev/null 2>&1 || true
if [[ ! -f /etc/default/tailscale ]]; then
    warn "no /etc/default/tailscale yet — set TAILSCALE_AUTHKEY there to enable auto-join"
fi

log "hardening applied"
