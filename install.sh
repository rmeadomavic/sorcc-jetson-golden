#!/usr/bin/env bash
# SORCC AI Kit installer for a Jetson Orin Nano Super (8 GB) running JetPack 7 or 6.
#
# Builds the whole kit from the internet on this Jetson. No second Jetson and no
# copied files are needed:
#   Language   Ollama with qwen3:4b-instruct
#   Imagery    ComfyUI with the class models and workflows
#   Detection  Hydra with YOLOv8n and the class config
#   Launcher   the SORCC AI Kit web page on port 8090 and the desktop shortcut
#
# It picks the build from the JetPack version it finds:
#   JetPack 7  ComfyUI and Hydra run natively from one pinned Python environment
#              (jetpack7/requirements.lock). Run scripts/jetpack7-test.sh first.
#   JetPack 6  ComfyUI and Hydra run in Docker (comfyui/Dockerfile, pinned Hydra image).
#
# Usage, from this repo's folder on the Jetson:
#   sudo ./install.sh HYDRA-1
#
# HYDRA-1 is the kit's name on the Detection dashboard. Give each kit its own number.
# Safe to re-run: finished steps are skipped, so after fixing a problem run it again.
#
# Options:
#   --user NAME   desktop account that gets the shortcut (default: the account that ran sudo)
#   --rebuild     rebuild the ComfyUI image (JetPack 6) or the Python environment (JetPack 7)
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Pinned versions. Every kit built from this commit gets the same software.
# ---------------------------------------------------------------------------
OLLAMA_VERSION="0.34.4"
LLM_MODEL="qwen3:4b-instruct"   # never llama3.2 (license) or plain qwen3:4b (thinking model)
HYDRA_IMAGE="ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d"
COMFY_IMAGE="comfyui-sorcc:latest"
YOLO_URL="https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt"
YOLO_SIZE=6549796
YOLO_SHA256="f59b3d833e2ff32e194b5bb8e08d211dc7c5bdf144b90d2c8412c47ccfc83b36"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SORCC=/opt/sorcc
LOG=/var/log/sorcc-install.log
TOTAL_STEPS=9
REBOOT_NEEDED=0
PLATFORM=""   # jp6 or jp7, set by the first step

usage() {
  cat <<EOF
Usage: sudo ./install.sh [--user NAME] [--rebuild] CALLSIGN

  CALLSIGN   this kit's name on the Detection dashboard, for example HYDRA-1
             (letters, numbers, - and _ only; use a different one for each kit)
EOF
}

# shellcheck source=scripts/sorcc-lib.sh
. "$REPO/scripts/sorcc-lib.sh"
on_error() {
  die "This command failed (install.sh line $1):" "  $2" \
    "Look at the lines just above for the reason. Network errors usually pass on a re-run."
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-}"
CALLSIGN=""
REBUILD=0
while (( $# )); do
  case "$1" in
    --user) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TARGET_USER="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) [[ -z "$CALLSIGN" ]] || { usage >&2; exit 2; }; CALLSIGN="$1"; shift ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run it with sudo:  sudo ./install.sh ${CALLSIGN:-HYDRA-1}" >&2
  exit 2
fi
[[ -n "$CALLSIGN" ]] || { usage >&2; exit 2; }
[[ "$CALLSIGN" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || { echo "Callsign '$CALLSIGN' is not valid." >&2; usage >&2; exit 2; }
if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]]; then
  echo "Run this from your normal desktop account with sudo (not as root), or pass --user NAME." >&2
  exit 2
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || { echo "Unknown user: $TARGET_USER" >&2; exit 2; }

install -d -m 0755 "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
printf '\n===== SORCC install started %s (repo %s) =====\n' "$(date -Is)" \
  "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Kit callsign: $CALLSIGN    Desktop user: $TARGET_USER"

# ---------------------------------------------------------------------------
step "Checking this Jetson"
# ---------------------------------------------------------------------------
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
# shellcheck source=/dev/null
. /etc/os-release
L4T_VERSION="$(dpkg-query -W -f '${Version}' nvidia-l4t-core 2>/dev/null | cut -d- -f1 || true)"
if [[ -z "$L4T_VERSION" && -f /etc/nv_tegra_release ]]; then
  L4T_VERSION="$(sed -nE '1s/^# R([0-9]+) .*REVISION: ([0-9.]+).*/\1.\2/p' /etc/nv_tegra_release)"
fi
L4T_MAJOR="${L4T_VERSION%%.*}"
info "Board:  $MODEL"
info "OS:     Ubuntu ${VERSION_ID:-?}    Jetson Linux (L4T): ${L4T_VERSION:-not found}"

if [[ "$MODEL" != *Jetson* && "$MODEL" != *Orin* ]]; then
  die "This does not look like a Jetson (board: $MODEL)."
fi
if [[ "${L4T_MAJOR:-0}" -ge 38 || "${VERSION_ID:-}" == 24.04 ]]; then
  PLATFORM=jp7
  info "JetPack 7: ComfyUI and Hydra will run natively (no Docker)"
elif [[ "${L4T_MAJOR:-0}" == 36 ]]; then
  # JetPack 6.2 (36.4.3) is the first release with Super mode; 6.0 and 6.1 are 36.3 and 36.4.0.
  if [[ "$(printf '%s\n' 36.4.3 "$L4T_VERSION" | sort -V | sed -n 1p)" != 36.4.3 ]]; then
    die "Jetson Linux $L4T_VERSION is too old (JetPack 6.0 or 6.1)." \
      "Use JetPack 7.2 or newer, or JetPack 6.2.x (36.4.3 or newer). See docs/jetpack7.md."
  fi
  PLATFORM=jp6
  info "JetPack 6: ComfyUI and Hydra will run in Docker"
else
  die "Unsupported Jetson Linux version: ${L4T_VERSION:-unknown}." \
    "Use JetPack 7.2 or newer, or JetPack 6.2.x (36.4.3 or newer). See docs/jetpack7.md."
fi
[[ "$MODEL" == *"Orin Nano"* ]] || warn "Built and tested on the Orin Nano Super dev kit; this board is '$MODEL'."
MEM_GB=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1000000 ))
(( MEM_GB >= 7 )) || die "This Jetson has about ${MEM_GB} GB of RAM. The kit needs the 8 GB Orin Nano."
[[ -e /run/reboot-required ]] && warn "Ubuntu says a reboot is pending. Reboot after this install finishes."

ROOT_DEV="$(findmnt -no SOURCE /)"
info "Root filesystem: $ROOT_DEV"

# Rough space check: only count what is not installed yet.
need_gb=5
if [[ "$PLATFORM" == jp7 ]]; then
  [[ -f "$SORCC/venv/.sorcc-lock" ]] || need_gb=$((need_gb + 10))
elif command -v docker >/dev/null 2>&1; then
  docker image inspect "$HYDRA_IMAGE" >/dev/null 2>&1 || need_gb=$((need_gb + 16))
  docker image inspect "$COMFY_IMAGE" >/dev/null 2>&1 || need_gb=$((need_gb + 16))
else
  need_gb=$((need_gb + 32))
fi
[[ -f "$SORCC/comfyui/models/checkpoints/revAnimated_v122.safetensors" ]] || need_gb=$((need_gb + 11))
[[ -d /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3 ]] || need_gb=$((need_gb + 3))
FREE_GB="$(df --output=avail -BG / | tail -1 | tr -dc '0-9')"
info "Free space: ${FREE_GB} GB (this run needs about ${need_gb} GB)"
(( FREE_GB >= need_gb )) || die "Not enough free disk space: ${FREE_GB} GB free, about ${need_gb} GB needed." \
  "Use a 256 GB or larger NVMe drive, or free up space, then re-run."

if [[ "$PLATFORM" == jp7 ]]; then
  urls="https://ollama.com https://huggingface.co https://github.com https://pypi.org https://download.pytorch.org"
else
  urls="https://ollama.com https://huggingface.co https://github.com https://ghcr.io/v2/ https://registry-1.docker.io/v2/"
fi
for url in $urls; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null || true)"
  [[ "$code" != 000 && -n "$code" ]] || die "Cannot reach $url" \
    "The installer needs internet access. Plug the Jetson into a network with internet and re-run."
done
info "Internet access OK"

# ---------------------------------------------------------------------------
if [[ "$PLATFORM" == jp7 ]]; then step "Installing system packages"; else step "Installing system packages, Docker, and the NVIDIA container runtime"; fi
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
systemctl stop ollama comfyui hydra-detect >/dev/null 2>&1 || true   # free memory on a re-run
retry apt-get update || die "apt-get update failed. Check the internet connection and the apt sources."
retry apt-get install -y --no-install-recommends \
  ca-certificates curl git openssl python3 python3-venv rsync v4l-utils zstd dbus libglib2.0-bin
if [[ "$PLATFORM" == jp7 ]]; then
  info "$(python3 --version) with venv"
elif ! command -v docker >/dev/null 2>&1; then
  info "Docker is not installed; installing docker.io"
  retry apt-get install -y docker.io
fi
if [[ "$PLATFORM" == jp6 ]]; then
systemctl enable --now docker >/dev/null
runtimes="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
if [[ "$runtimes" != *nvidia* ]]; then
  info "Adding the NVIDIA runtime to Docker"
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    apt-get install -y nvidia-container-toolkit || apt-get install -y nvidia-container \
      || die "Could not install the NVIDIA container runtime (nvidia-container-toolkit)." \
        "Install it with: sudo apt-get install nvidia-jetpack   then re-run."
  fi
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
  runtimes="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
fi
[[ "$runtimes" == *nvidia* ]] || die "Docker still has no 'nvidia' runtime." \
  "Try: sudo apt-get install --reinstall nvidia-container-toolkit && sudo systemctl restart docker"
info "Docker $(docker version --format '{{.Server.Version}}') with the NVIDIA runtime"
fi

# ---------------------------------------------------------------------------
step "Installing the Chromium browser"
# ---------------------------------------------------------------------------
if [[ ! -x /snap/bin/chromium ]]; then
  retry snap install chromium || die "Could not install Chromium (snap install chromium)." \
    "See 'Chromium will not install or start' in docs/troubleshooting.md."
fi
# Freeze snapd at the working version; a snapd update has broken Chromium on Jetsons before.
snap refresh --hold snapd >/dev/null 2>&1 || true
if timeout 120 runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" /snap/bin/chromium --version >/dev/null 2>&1; then
  info "$(runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" /snap/bin/chromium --version 2>/dev/null)"
else
  warn "Chromium is installed but did not start in a test. See 'Chromium will not install or start' in docs/troubleshooting.md."
fi

# ---------------------------------------------------------------------------
step "Setting Super power mode (MAXN_SUPER)"
# ---------------------------------------------------------------------------
SUPER_ID="$(sed -nE 's/^<[[:space:]]*POWER_MODEL[[:space:]]+ID=([0-9]+)[[:space:]]+NAME=MAXN_SUPER[[:space:]]*>.*/\1/p' /etc/nvpmodel.conf 2>/dev/null | sed -n 1p || true)"
CURRENT_MODE="$(nvpmodel -q 2>/dev/null | sed -nE 's/.*Power Mode:[[:space:]]*//p' | sed -n 1p || true)"
if [[ -z "$SUPER_ID" ]]; then
  if [[ "$PLATFORM" == jp7 ]]; then
    warn "MAXN_SUPER is not available, so the GPU is capped (about 624 MHz instead of 1020). The JetPack 7.2 USB installer leaves Super mode off; see 'Super mode' in docs/jetpack7.md."
  else
    warn "MAXN_SUPER is not available, so the GPU stays slower. The board was flashed without the Super configuration; see docs/reflash-jetpack6-nvme.md."
  fi
elif [[ "$CURRENT_MODE" == MAXN_SUPER ]]; then
  info "Already in MAXN_SUPER"
else
  info "Switching from ${CURRENT_MODE:-unknown} to MAXN_SUPER (mode $SUPER_ID)"
  printf 'NO\n' | nvpmodel -m "$SUPER_ID" >/dev/null 2>&1 || true
  if [[ "$(nvpmodel -q 2>/dev/null | sed -nE 's/.*Power Mode:[[:space:]]*//p' | sed -n 1p || true)" != MAXN_SUPER ]]; then
    info "MAXN_SUPER takes effect after a reboot"
    REBOOT_NEEDED=1
  fi
fi

# ---------------------------------------------------------------------------
step "Language: Ollama $OLLAMA_VERSION and $LLM_MODEL"
# ---------------------------------------------------------------------------
installed_ollama="$(ollama -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tail -1 || true)"
if [[ "$installed_ollama" != "$OLLAMA_VERSION" ]]; then
  info "Installing Ollama $OLLAMA_VERSION (found: ${installed_ollama:-none})"
  retry curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
  OLLAMA_VERSION="$OLLAMA_VERSION" sh /tmp/ollama-install.sh
  rm -f /tmp/ollama-install.sh
else
  info "Ollama $OLLAMA_VERSION already installed"
fi
# Class settings: run the model on the CPU (keeps the 8 GB of shared memory free for the
# other tools, and is the configuration that passed acceptance) with a 4K context window.
install -d -m 0755 /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="CUDA_VISIBLE_DEVICES="
Environment="OLLAMA_CONTEXT_LENGTH=4096"
EOF
systemctl daemon-reload
systemctl stop comfyui hydra-detect >/dev/null 2>&1 || true
systemctl restart ollama
for _ in $(seq 1 60); do curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:11434/api/version >/dev/null || die "Ollama did not start. Check: journalctl -u ollama -n 50"
if ollama show "$LLM_MODEL" >/dev/null 2>&1; then
  info "$LLM_MODEL already downloaded"
else
  info "Downloading $LLM_MODEL (about 2.5 GB)"
  retry ollama pull "$LLM_MODEL" || die "Could not download $LLM_MODEL from ollama.com."
fi
# Class rule: only the instruct model. Remove models that must not ship.
models_now="$(ollama list 2>/dev/null | awk 'NR > 1 {print $1}' || true)"
for bad in $models_now; do
  case "$bad" in
    llama3.2*|qwen3:4b|qwen3:latest) info "Removing $bad (not allowed on class kits)"; ollama rm "$bad" >/dev/null ;;
  esac
done
info "Checking that $LLM_MODEL answers (this can take a minute)"
reply="$(curl -fsS --max-time 300 http://127.0.0.1:11434/api/generate \
  -d "{\"model\":\"$LLM_MODEL\",\"prompt\":\"Reply with exactly: READY\",\"stream\":false}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("response",""))' || true)"
[[ "$reply" == *READY* ]] || warn "$LLM_MODEL did not answer the test prompt (got: '${reply:0:80}'). The smoke test will check it again."
systemctl stop ollama
systemctl disable ollama >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "Detection: Hydra, YOLO weights, and class config"
# ---------------------------------------------------------------------------
if [[ "$PLATFORM" == jp7 ]]; then
  jp7_app_source hydra rmeadomavic/Hydra "$HYDRA_COMMIT"
  (( REBUILD )) && rm -f "$VENV/.sorcc-lock"
  jp7_python_env
  info "Checking that PyTorch can use the GPU"
  gpu_check="$(jp7_gpu_check 2>&1)" || {
    printf '%s\n' "$gpu_check" | tail -8
    die "PyTorch could not use the GPU correctly." \
      "See 'The GPU check failed on JetPack 7' in docs/troubleshooting.md."
  }
  info "$(printf '%s\n' "$gpu_check" | tail -1)"
else
if docker image inspect "$HYDRA_IMAGE" >/dev/null 2>&1; then
  info "Hydra image already downloaded"
else
  info "Downloading the Hydra image (about 7 GB)"
  retry docker pull "$HYDRA_IMAGE" || die "Could not download the Hydra image from ghcr.io."
fi
info "Checking that Docker containers can use the GPU"
if ! gpu_check="$(docker run --rm --runtime nvidia "$HYDRA_IMAGE" python3 -c \
  'import torch; torch.zeros(1).cuda(); print("CUDA OK:", torch.cuda.get_device_name(0))' 2>&1)"; then
  printf '%s\n' "$gpu_check" | tail -5
  die "A test container could not use the GPU." \
    "The usual cause is a JetPack mismatch or a broken NVIDIA container runtime." \
    "See 'A test container could not use the GPU' in docs/troubleshooting.md."
fi
info "$(printf '%s\n' "$gpu_check" | tail -1)"
fi

install -d -m 0755 "$SORCC" "$SORCC/hydra" "$SORCC/hydra/models"
fetch "$YOLO_URL" "$SORCC/hydra/models/yolov8n.pt" "$YOLO_SIZE" "$YOLO_SHA256"

# Keep this kit's existing Hydra token on a re-run; otherwise make a new one.
HYDRA_TOKEN="$(sed -nE 's/^api_token[[:space:]]*=[[:space:]]*([0-9a-f]{64})[[:space:]]*$/\1/p' "$SORCC/hydra/config.ini" 2>/dev/null | sed -n 1p || true)"
[[ -n "$HYDRA_TOKEN" ]] || HYDRA_TOKEN="$(openssl rand -hex 32)"
[[ -f "$SORCC/hydra/config.ini" ]] && cp -f "$SORCC/hydra/config.ini" "$SORCC/hydra/config.ini.before-install"
install -m 0644 "$REPO/hydra/config.ini" "$SORCC/hydra/config.ini"
sed -i -E "s/^api_token[[:space:]]*=.*/api_token = $HYDRA_TOKEN/" "$SORCC/hydra/config.ini"
sed -i -E "/^\[tak\]/,/^\[/{s/^callsign[[:space:]]*=.*/callsign = $CALLSIGN/}" "$SORCC/hydra/config.ini"
chown -R root:root "$SORCC/hydra"
info "Hydra callsign $CALLSIGN"

# ---------------------------------------------------------------------------
if [[ "$PLATFORM" == jp7 ]]; then step "Imagery: ComfyUI and models"; else step "Imagery: building the ComfyUI image and downloading models"; fi
# ---------------------------------------------------------------------------
if [[ "$PLATFORM" == jp7 ]]; then
  jp7_app_source comfyui comfyanonymous/ComfyUI "$COMFYUI_COMMIT"
else
COMFY_BUILD_ID="$(cat "$REPO/comfyui/Dockerfile" "$REPO/comfyui/requirements.lock" | sha256sum | cut -c1-16)"
current_build="$(docker image inspect -f '{{index .Config.Labels "sorcc.build-id"}}' "$COMFY_IMAGE" 2>/dev/null || true)"
if [[ "$current_build" == "$COMFY_BUILD_ID" && $REBUILD -eq 0 ]]; then
  info "ComfyUI image is up to date"
else
  COMFY_BASE="$(sed -nE 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "$REPO/comfyui/Dockerfile" | sed -n 1p)"
  if ! docker image inspect "$COMFY_BASE" >/dev/null 2>&1; then
    info "Downloading the ComfyUI base image (about 7 GB)"
    retry docker pull "$COMFY_BASE" || die "Could not download $COMFY_BASE from Docker Hub."
  fi
  info "Building the ComfyUI image (10 to 20 minutes)"
  docker build --label "sorcc.build-id=$COMFY_BUILD_ID" -t "$COMFY_IMAGE" "$REPO/comfyui" \
    || die "The ComfyUI image build failed. Scroll up for the first error." \
      "If it was a network error, just re-run; finished build layers are reused."
fi
fi

C="$SORCC/comfyui"
install_comfy_files
fetch_comfy_models
chown -R "$TARGET_USER:$TARGET_USER" "$C"

# ---------------------------------------------------------------------------
step "Installing the launcher, services, and desktop"
# ---------------------------------------------------------------------------
install -m 0755 "$REPO/scripts/sorcc_launcher.py" "$SORCC/sorcc_launcher.py"
install -m 0755 "$REPO/scripts/sorcc-jetson-smoke-test.sh" "$SORCC/sorcc-jetson-smoke-test.sh"
install -m 0755 "$REPO/scripts/sorcc-diag" /usr/local/bin/sorcc-diag
chown root:root "$SORCC/sorcc_launcher.py" "$SORCC/sorcc-jetson-smoke-test.sh"

cat >/etc/systemd/system/sorcc-launcher.service <<EOF
[Unit]
Description=SORCC AI Kit Launcher (student front door, :8090)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SORCC/sorcc_launcher.py
Restart=always
RestartSec=3
User=$TARGET_USER

[Install]
WantedBy=multi-user.target
EOF

# Heavy tools. Each one drops caches and compacts memory first so it gets the most of 8 GB.
if [[ "$PLATFORM" == jp7 ]]; then
cat >/etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI (SORCC AI Kit - Imagery)
After=network.target

[Service]
Type=simple
WorkingDirectory=$SORCC/app/comfyui
Environment=PYTHONUNBUFFERED=1
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=$VENV/bin/python main.py --base-directory $C --listen 0.0.0.0 --port 8188 \\
  --disable-all-custom-nodes --whitelist-custom-nodes sorcc_student \\
  --cpu-vae --lowvram --disable-dynamic-vram --preview-method none
TimeoutStopSec=15
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/hydra-detect.service <<EOF
[Unit]
Description=Hydra Detect (SORCC AI Kit - Detection)
After=network.target

[Service]
Type=simple
WorkingDirectory=$SORCC/app/hydra
Environment=PYTHONUNBUFFERED=1 YOLO_OFFLINE=1
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=$VENV/bin/python -m hydra_detect --config $SORCC/hydra/config.ini
TimeoutStopSec=15
Restart=no

[Install]
WantedBy=multi-user.target
EOF
else
cat >/etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI (SORCC AI Kit - Imagery)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker rm -f comfyui
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=/usr/bin/docker run --rm --name comfyui --runtime nvidia --network host \\
  -v $C/models:/opt/ComfyUI/models \\
  -v $C/output:/opt/ComfyUI/output \\
  -v $C/input:/opt/ComfyUI/input \\
  -v $C/user:/opt/ComfyUI/user \\
  -v $C/workflows/SORCC-START-HERE.json:/opt/ComfyUI/user/default/workflows/SORCC-START-HERE.json:ro \\
  -v $C/workflows/SORCC-QUALITY-20-STEP.json:/opt/ComfyUI/user/default/workflows/SORCC-QUALITY-20-STEP.json:ro \\
  -v $C/workflows/SORCC-cheat-sheet.json:/opt/ComfyUI/user/default/workflows/SORCC-cheat-sheet.json:ro \\
  -v $C/custom_nodes/sorcc_student:/opt/ComfyUI/custom_nodes/sorcc_student:ro \\
  $COMFY_IMAGE python3 main.py --listen 0.0.0.0 --port 8188 \\
  --disable-all-custom-nodes --whitelist-custom-nodes sorcc_student \\
  --cpu-vae --lowvram --disable-dynamic-vram --preview-method none
ExecStop=/usr/bin/docker stop -t 10 comfyui
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/hydra-detect.service <<EOF
[Unit]
Description=Hydra Detect (SORCC AI Kit - Detection)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker rm -f hydra-detect
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=/usr/bin/docker run --rm --name hydra-detect --runtime nvidia --network host --privileged \\
  -v /dev:/dev -v $SORCC/hydra:/config -v $SORCC/hydra/models:/data/models \\
  $HYDRA_IMAGE python3 -m hydra_detect --config /config/config.ini
ExecStop=/usr/bin/docker stop -t 10 hydra-detect
Restart=no

[Install]
WantedBy=multi-user.target
EOF
fi

# The launcher (running as the desktop user) may start and stop only these three tools.
# Validate a temp copy first: a broken file in /etc/sudoers.d would disable sudo entirely.
SYSTEMCTL="$(command -v systemctl)"
SUDOERS_TMP="$(mktemp)"
cat >"$SUDOERS_TMP" <<EOF
$TARGET_USER ALL=(root) NOPASSWD: $SYSTEMCTL start ollama, $SYSTEMCTL stop ollama, $SYSTEMCTL reset-failed ollama, $SYSTEMCTL start comfyui, $SYSTEMCTL stop comfyui, $SYSTEMCTL reset-failed comfyui, $SYSTEMCTL start hydra-detect, $SYSTEMCTL stop hydra-detect, $SYSTEMCTL reset-failed hydra-detect
EOF
if ! visudo -cf "$SUDOERS_TMP" >/dev/null; then
  rm -f "$SUDOERS_TMP"
  die "The generated sudoers rule did not validate, so it was not installed."
fi
install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/sorcc-ai
rm -f "$SUDOERS_TMP"

# Logging: persistent and capped on NVMe; RAM-only on microSD to spare the card.
rm -f /etc/systemd/journald.conf.d/sorcc-volatile.conf
install -d -m 0755 /etc/systemd/journald.conf.d
if [[ "$ROOT_DEV" == /dev/mmcblk* ]]; then
  printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=128M\n' >/etc/systemd/journald.conf.d/sorcc.conf
else
  printf '[Journal]\nStorage=persistent\nSystemMaxUse=200M\n' >/etc/systemd/journald.conf.d/sorcc.conf
fi

# Desktop: wallpaper, SORCC AI Kit shortcut, and Chromium as the default browser.
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/Desktop" "$TARGET_HOME/Pictures" \
  "$TARGET_HOME/.config" "$TARGET_HOME/.local" "$TARGET_HOME/.local/share" "$TARGET_HOME/.local/share/applications"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0644 "$REPO/assets/sorcc-wallpaper.png" "$TARGET_HOME/Pictures/sorcc-wallpaper.png"
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
cat >"$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SORCC AI Kit
Comment=Open the offline Language, Imagery, and Detection tools
Exec=xdg-open http://127.0.0.1:8090/
Icon=applications-science
Terminal=false
Categories=Education;
StartupNotify=true
EOF
cp "$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/mimeapps.list" \
  "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" \
  "$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"
chmod 0644 "$TARGET_HOME/.config/mimeapps.list" "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop"
chmod 0755 "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"
PIC="file://$TARGET_HOME/Pictures/sorcc-wallpaper.png"
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" dbus-run-session -- bash -c '
  gsettings set org.gnome.desktop.background picture-uri "'"$PIC"'"
  gsettings set org.gnome.desktop.background picture-uri-dark "'"$PIC"'"
  gsettings set org.gnome.desktop.background picture-options centered
  gsettings set org.gnome.desktop.background color-shading-type solid
  gsettings set org.gnome.desktop.background primary-color "#000000"
  gsettings set org.gnome.desktop.background secondary-color "#000000"
  gio set "'"$TARGET_HOME"'/Desktop/SORCC-AI-Kit.desktop" metadata::trusted true
' >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl restart systemd-journald
[[ "$PLATFORM" == jp6 ]] && systemctl enable --now docker >/dev/null
systemctl enable --now sorcc-launcher >/dev/null
systemctl restart sorcc-launcher
systemctl disable ollama comfyui hydra-detect >/dev/null 2>&1 || true
systemctl stop ollama comfyui hydra-detect >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "Final check"
# ---------------------------------------------------------------------------
for _ in $(seq 1 30); do curl -fsS http://127.0.0.1:8090/status >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:8090/status >/dev/null || die "The launcher did not start. Check: journalctl -u sorcc-launcher -n 50"
info "Launcher is up at http://127.0.0.1:8090/"
[[ -c /dev/video0 ]] || warn "No USB camera found (/dev/video0). Plug in the webcam before running the smoke test."

printf '\n%s==================== INSTALL COMPLETE ====================%s\n' "$G" "$N"
echo "  Kit callsign:     $CALLSIGN"
if [[ "$PLATFORM" == jp7 ]]; then echo "  Build:            JetPack 7 (native, no Docker)"; else echo "  Build:            JetPack 6 (Docker)"; fi
echo "  Hydra token hash: $(printf %s "$HYDRA_TOKEN" | sha256sum | cut -c1-16) (the token itself stays in $SORCC/hydra/config.ini)"
echo "  Install log:      $LOG"
if (( ${#WARNINGS[@]} )); then
  printf '\n%s  Warnings to look at:%s\n' "$Y" "$N"
  printf '   - %s\n' "${WARNINGS[@]}"
fi
echo
echo "  Next:"
if (( REBOOT_NEEDED )); then
  echo "   1. Reboot now (needed for Super power mode):   sudo reboot"
else
  echo "   1. Reboot once so everything starts clean:      sudo reboot"
fi
echo "   2. With the USB camera plugged in, run the test: sudo $SORCC/sorcc-jetson-smoke-test.sh"
echo "   3. Double-click 'SORCC AI Kit' on the desktop and try all three tools."
echo "      (First time only: right-click the icon and choose 'Allow Launching'.)"
echo
echo "INSTALL_OK callsign=$CALLSIGN"
