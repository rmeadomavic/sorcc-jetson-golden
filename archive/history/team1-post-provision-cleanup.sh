#!/usr/bin/env bash
# Remove Team 1 provisioning duplicates after full acceptance.
set -euo pipefail

[[ "${1:-}" == "--execute-team1-cleanup" ]] || {
  echo "Refusing to run without --execute-team1-cleanup" >&2
  exit 2
}
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }
[[ "$(hostname)" == "team1-desktop" ]] || { echo "Wrong host." >&2; exit 3; }

COMFY_ID='sha256:4e95d450bc7cee956786442302f632800515cd00d37bd1952d8c2ece3f085c5c'
HYDRA_REF='ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d'

[[ "$(docker image inspect --format '{{.Id}}' comfyui-sorcc:latest)" == "$COMFY_ID" ]]
docker image inspect "$HYDRA_REF" >/dev/null
[[ -f /opt/sorcc/comfyui/workflows/SORCC-START-HERE.json ]]
[[ -f /opt/sorcc/hydra/models/yolov8n.pt ]]

curl -fsS -X POST http://127.0.0.1:8090/stop >/dev/null 2>&1 || true
rm -rf -- /home/team1/sorcc-stage
find /opt/sorcc/comfyui/output -maxdepth 1 -type f -name '*.png' -delete
apt-get clean

if [[ -f /home/team1/.ssh/authorized_keys ]]; then
  sed -i '/[[:space:]]sorcc3@sorcc3-desktop$/d' /home/team1/.ssh/authorized_keys
  chown team1:team1 /home/team1/.ssh/authorized_keys
  chmod 0600 /home/team1/.ssh/authorized_keys
fi

[[ ! -e /home/team1/sorcc-stage ]]
[[ "$(docker image inspect --format '{{.Id}}' comfyui-sorcc:latest)" == "$COMFY_ID" ]]
docker image inspect "$HYDRA_REF" >/dev/null
grep -q 'kyle-remarkable$' /home/team1/.ssh/authorized_keys
! grep -q 'sorcc3@sorcc3-desktop$' /home/team1/.ssh/authorized_keys

sync
printf 'TEAM1_CLEANUP_OK free_bytes=%s\n' "$(df --output=avail -B1 / | tail -1 | tr -d ' ')"
