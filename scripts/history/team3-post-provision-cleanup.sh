#!/usr/bin/env bash
# Remove Team 3 test models, superseded images, caches, and generated bench output.
set -euo pipefail

[[ "${1:-}" == "--execute-team3-cleanup" ]] || {
  echo "Refusing to run without --execute-team3-cleanup" >&2
  exit 2
}
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }
[[ "$(hostname)" == "sorcc3-desktop" ]] || { echo "Wrong host." >&2; exit 3; }

COMFY_ID='sha256:4e95d450bc7cee956786442302f632800515cd00d37bd1952d8c2ece3f085c5c'
HYDRA_REF='ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d'
LLAMA_MANIFEST='/usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/llama3.2/3b'

[[ "$(docker image inspect --format '{{.Id}}' comfyui-sorcc:latest)" == "$COMFY_ID" ]]
docker image inspect "$HYDRA_REF" >/dev/null
[[ -f "$LLAMA_MANIFEST" ]]

curl -fsS -X POST http://127.0.0.1:8090/stop >/dev/null 2>&1 || true

systemctl start ollama
for _ in $(seq 1 90); do
  curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:11434/api/tags >/dev/null
if [[ -f /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b ]]; then
  /usr/local/bin/ollama rm qwen3:4b
fi
systemctl stop ollama

obsolete_images=(
  'comfyui-sorcc:torch27'
  'comfyui-sorcc:candidate'
  'comfyui-sorcc:pre-torch27-20260720'
  'dustynv/ollama:0.6.8-r36.4-cu126-22.04'
  'dustynv/pytorch:2.7-r36.4.0-cu128-24.04'
  'dustynv/comfyui:r36.4.3-cu128-24.04'
)
for image in "${obsolete_images[@]}"; do
  docker image rm "$image" >/dev/null 2>&1 || true
done
docker builder prune -af >/dev/null
apt-get clean
find /opt/sorcc/comfyui/output -maxdepth 1 -type f -name '*.png' -delete

[[ -f "$LLAMA_MANIFEST" ]]
[[ ! -e /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b ]]
[[ "$(docker image inspect --format '{{.Id}}' comfyui-sorcc:latest)" == "$COMFY_ID" ]]
docker image inspect "$HYDRA_REF" >/dev/null
for image in "${obsolete_images[@]}"; do
  ! docker image inspect "$image" >/dev/null 2>&1
done
[[ -z "$(find /opt/sorcc/comfyui/output -maxdepth 1 -type f -name '*.png' -print -quit)" ]]

sync
printf 'TEAM3_CLEANUP_OK free_bytes=%s\n' "$(df --output=avail -B1 / | tail -1 | tr -d ' ')"
