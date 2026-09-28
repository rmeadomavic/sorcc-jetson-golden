#!/usr/bin/env bash
# JetPack 7 readiness test for the SORCC AI Kit. Run it on one Jetson before deciding
# between the JetPack 7 build and the JetPack 6 backup:
#
#   sudo ./scripts/jetpack7-test.sh
#
# It checks Super mode and the GPU clock, proves PyTorch computes correctly on the GPU,
# renders the real START HERE image on the GPU and checks it is not blank, and runs the
# YOLO detector on a sample video. It ends with a plain recommendation.
#
# About 20 to 30 minutes, mostly downloads. Nothing is wasted: it builds the same Python
# environment and downloads the same models that install.sh uses. It runs everything on
# 127.0.0.1 and leaves no services running. Safe to re-run.
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SORCC=/opt/sorcc
LOG=/var/log/sorcc-jetpack7-test.log
TOTAL_STEPS=5
PLATFORM=jp7
# shellcheck source=scripts/sorcc-lib.sh
. "$REPO/scripts/sorcc-lib.sh"
trap 'die "This command failed (jetpack7-test.sh line $LINENO):" "  $BASH_COMMAND"' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Run it with sudo:  sudo ./scripts/jetpack7-test.sh" >&2
  exit 2
fi
install -d -m 0755 "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1
printf '===== SORCC JetPack 7 test %s (repo %s) =====\n' "$(date -Is)" \
  "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

declare -A RESULT DETAIL
record() { RESULT[$1]="$2"; DETAIL[$1]="$3"; info "$2: $3"; }
COMFY_PID=""
# Stop ComfyUI and wait until it has exited, so its GPU memory is free before the next check.
cleanup() {
  [[ -n "$COMFY_PID" ]] || return 0
  kill "$COMFY_PID" 2>/dev/null || true
  for _ in $(seq 30); do kill -0 "$COMFY_PID" 2>/dev/null || break; sleep 1; done
  kill -9 "$COMFY_PID" 2>/dev/null || true
  wait "$COMFY_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
step "JetPack version, Super mode, and GPU clock"
# ---------------------------------------------------------------------------
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
UBUNTU="$(. /etc/os-release; echo "${VERSION_ID:-?}")"
L4T="$(dpkg-query -W -f '${Version}' nvidia-l4t-core 2>/dev/null | cut -d- -f1 || true)"
info "Board: $MODEL"
info "Ubuntu $UBUNTU, Jetson Linux ${L4T:-unknown}"
if [[ "${L4T%%.*}" == 36 ]]; then
  echo
  echo "This Jetson is on JetPack 6, so there is nothing to test. Build the kit with:"
  echo "  sudo ./install.sh HYDRA-1"
  exit 0
fi
if [[ "$UBUNTU" != 24.04 && "${L4T%%.*}" -lt 38 ]]; then
  die "This does not look like JetPack 7 (Ubuntu $UBUNTU, Jetson Linux ${L4T:-unknown})."
fi

has_super=no
grep -q 'NAME=MAXN_SUPER' /etc/nvpmodel.conf 2>/dev/null && has_super=yes
mode="$(nvpmodel -q 2>/dev/null | sed -nE 's/.*Power Mode:[[:space:]]*//p' | sed -n 1p || true)"
gpu_freqs="$(find /sys/devices -path '*gpu*/devfreq/*' -name available_frequencies -print -quit 2>/dev/null || true)"
gpu_dir="${gpu_freqs%/*}"
hw_mhz=0; cap_mhz=0
if [[ -n "$gpu_freqs" ]]; then
  hw_mhz=$(( $(tr ' ' '\n' <"$gpu_dir/available_frequencies" | grep -E '^[0-9]+$' | sort -n | tail -1) / 1000000 ))
  cap_mhz=$(( $(cat "$gpu_dir/max_freq") / 1000000 ))
fi
info "Power mode now: ${mode:-unknown}    MAXN_SUPER available: $has_super"
if (( hw_mhz > 0 )); then
  info "GPU top clock: ${hw_mhz} MHz (current limit ${cap_mhz} MHz)"
else
  info "GPU top clock: unknown (could not read it from /sys)"
fi
if [[ "$has_super" == yes ]] && (( hw_mhz == 0 || hw_mhz >= 1000 )); then
  if (( hw_mhz > 0 )); then record super PASS "Super mode available, GPU can reach ${hw_mhz} MHz"; else record super PASS "Super mode available"; fi
elif [[ "$has_super" == yes ]]; then
  record super WARN "MAXN_SUPER is listed but the GPU tops out at ${hw_mhz} MHz (want 1020). Works, just slower; see 'Super mode' in docs/jetpack7.md"
else
  record super WARN "Super mode is off, so the GPU runs slower (about 624 MHz instead of 1020). Everything still works; see 'Super mode' in docs/jetpack7.md"
fi

# ---------------------------------------------------------------------------
step "Installing Python and PyTorch for the GPU (same environment install.sh uses)"
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
systemctl stop ollama comfyui hydra-detect >/dev/null 2>&1 || true
retry apt-get update || die "apt-get update failed. Check the internet connection."
retry apt-get install -y --no-install-recommends ca-certificates curl python3 python3-venv rsync
jp7_app_source comfyui comfyanonymous/ComfyUI "$COMFYUI_COMMIT"
jp7_python_env

# ---------------------------------------------------------------------------
step "GPU math check"
# ---------------------------------------------------------------------------
if out="$(jp7_gpu_check 2>&1)"; then
  record gpu PASS "$(printf '%s\n' "$out" | tail -1 | sed 's/^OK: //')"
else
  printf '%s\n' "$out" | tail -8
  record gpu FAIL "$(printf '%s\n' "$out" | tail -1)"
fi

# ---------------------------------------------------------------------------
step "Imagery: rendering the START HERE image on the GPU"
# ---------------------------------------------------------------------------
if [[ "${RESULT[gpu]}" != PASS ]]; then
  record imagery SKIP "skipped because the GPU math check failed"
else
  install_comfy_files
  fetch_comfy_models 'dreamshaper_8|lcm-lora'
  comfy_log="$SORCC/jetpack7-test-comfyui.log"
  (cd "$SORCC/app/comfyui" && exec "$VENV/bin/python" main.py --base-directory "$SORCC/comfyui" \
    --listen 127.0.0.1 --port 8188 --disable-all-custom-nodes --whitelist-custom-nodes sorcc_student \
    --cpu-vae --lowvram --disable-dynamic-vram --preview-method none) >"$comfy_log" 2>&1 &
  COMFY_PID=$!
  info "Starting ComfyUI (log: $comfy_log)"
  up=no
  for _ in $(seq 1 240); do
    curl -fsS -o /dev/null http://127.0.0.1:8188/system_stats 2>/dev/null && { up=yes; break; }
    kill -0 "$COMFY_PID" 2>/dev/null || break
    sleep 1
  done
  if [[ "$up" != yes ]]; then
    tail -20 "$comfy_log"
    record imagery FAIL "ComfyUI did not start; see $comfy_log"
  else
    info "Rendering (the first image loads the model, about 1 to 2 minutes)"
    if out="$("$VENV/bin/python" - "$REPO/comfyui/workflows/SORCC-START-HERE.json" "$SORCC/comfyui/output" <<'PY' 2>&1
import json, os, sys, time, urllib.request
from PIL import Image, ImageStat
base = 'http://127.0.0.1:8188'
graph = json.load(open(sys.argv[1]))
n = {str(x['id']): x for x in graph['nodes']}
w = {
 '1': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': n['1']['widgets_values'][0]}},
 '2': {'class_type': 'CLIPSetLastLayer', 'inputs': {'clip': ['1', 1], 'stop_at_clip_layer': n['2']['widgets_values'][0]}},
 '3': {'class_type': 'LoraLoader', 'inputs': {'model': ['1', 0], 'clip': ['2', 0], 'lora_name': n['3']['widgets_values'][0],
       'strength_model': n['3']['widgets_values'][1], 'strength_clip': n['3']['widgets_values'][2]}},
 '4': {'class_type': 'CLIPTextEncode', 'inputs': {'text': n['4']['widgets_values'][0], 'clip': ['3', 1]}},
 '5': {'class_type': 'CLIPTextEncode', 'inputs': {'text': n['5']['widgets_values'][0], 'clip': ['3', 1]}},
 '6': {'class_type': 'EmptyLatentImage', 'inputs': {'width': 256, 'height': 256, 'batch_size': 1}},
 '7': {'class_type': 'KSampler', 'inputs': {'seed': 42, 'steps': n['7']['widgets_values'][2], 'cfg': n['7']['widgets_values'][3],
       'sampler_name': n['7']['widgets_values'][4], 'scheduler': n['7']['widgets_values'][5], 'denoise': 1.0,
       'model': ['3', 0], 'positive': ['4', 0], 'negative': ['5', 0], 'latent_image': ['6', 0]}},
 '8': {'class_type': 'VAEDecode', 'inputs': {'samples': ['7', 0], 'vae': ['1', 2]}},
 '9': {'class_type': 'SaveImage', 'inputs': {'filename_prefix': 'sorcc_jetpack7_test', 'images': ['8', 0]}}}
req = urllib.request.Request(base + '/prompt', data=json.dumps({'prompt': w}).encode(),
                             headers={'Content-Type': 'application/json'})
t = time.time()
pid = json.load(urllib.request.urlopen(req, timeout=30))['prompt_id']
while time.time() - t < 600:
    h = json.load(urllib.request.urlopen(base + '/history/' + pid, timeout=10))
    if pid in h:
        e = h[pid]
        if e.get('status', {}).get('status_str') != 'success':
            print('render error:', json.dumps(e.get('status', {}))[:400]); sys.exit(2)
        im = [i for o in e.get('outputs', {}).values() for i in o.get('images', [])][0]
        path = os.path.join(sys.argv[2], im.get('subfolder', ''), im['filename'])
        st = ImageStat.Stat(Image.open(path).convert('L'))
        print(f"{path} in {time.time() - t:.0f} s, brightness {st.mean[0]:.0f}, contrast {st.stddev[0]:.0f}")
        sys.exit(0 if st.stddev[0] >= 10 else 3)
    time.sleep(2)
print('render timed out after 600 s'); sys.exit(4)
PY
)"; then
      record imagery PASS "real image rendered: $(printf '%s\n' "$out" | tail -1)"
    else
      rc=$?
      printf '%s\n' "$out" | tail -5
      if [[ $rc -eq 3 ]]; then
        record imagery FAIL "the image came out blank: $(printf '%s\n' "$out" | tail -1)"
      else
        record imagery FAIL "$(printf '%s\n' "$out" | tail -1)"
      fi
    fi
  fi
  cleanup; COMFY_PID=""
fi

# ---------------------------------------------------------------------------
step "Detection: YOLO on the sample video"
# ---------------------------------------------------------------------------
if [[ "${RESULT[gpu]}" != PASS ]]; then
  record detection SKIP "skipped because the GPU math check failed"
else
  fetch "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt" \
    "$SORCC/hydra/models/yolov8n.pt" 6549796 f59b3d833e2ff32e194b5bb8e08d211dc7c5bdf144b90d2c8412c47ccfc83b36
  if out="$(YOLO_OFFLINE=1 "$VENV/bin/python" - "$SORCC/hydra/models/yolov8n.pt" "$REPO/assets/people-detection.mp4" <<'PY' 2>&1
import sys, time, cv2
from ultralytics import YOLO
model = YOLO(sys.argv[1])
cap = cv2.VideoCapture(sys.argv[2])
frames = []
while len(frames) < 150:
    ok, f = cap.read()
    if not ok: break
    frames.append(f)
if len(frames) < 50:
    print(f'could not read the sample video ({len(frames)} frames)'); sys.exit(2)
for f in frames[:10]:
    model.predict(f, device=0, imgsz=416, conf=0.45, verbose=False)   # warm-up
t = time.time(); hits = 0
for f in frames[10:]:
    r = model.predict(f, device=0, imgsz=416, conf=0.45, verbose=False)[0]
    hits += int((r.boxes.cls == 0).any())
fps = (len(frames) - 10) / (time.time() - t)
share = hits / (len(frames) - 10)
print(f'{fps:.0f} FPS on the GPU, a person found in {share:.0%} of frames')
sys.exit(0 if fps >= 10 and share >= 0.1 else 3)
PY
)"; then
    record detection PASS "$(printf '%s\n' "$out" | tail -1)"
  else
    printf '%s\n' "$out" | tail -5
    record detection FAIL "$(printf '%s\n' "$out" | tail -1)"
  fi
fi

# ---------------------------------------------------------------------------
printf '\n%s==================== JETPACK 7 TEST RESULT ====================%s\n' "$G" "$N"
for k in super gpu imagery detection; do
  printf '  %-10s %-5s %s\n' "$k" "${RESULT[$k]:-?}" "${DETAIL[$k]:-}"
done
echo
if [[ "${RESULT[gpu]}" == PASS && "${RESULT[imagery]}" == PASS && "${RESULT[detection]}" == PASS ]]; then
  echo "  RECOMMENDATION: use JetPack 7. Build each kit with:  sudo ./install.sh HYDRA-1"
  if [[ "${RESULT[super]}" != PASS ]]; then
    echo "  First turn on Super mode for full speed: see 'Super mode' in docs/jetpack7.md."
  fi
  verdict=0
else
  echo "  RECOMMENDATION: use the JetPack 6 backup. JetPack 7 did not pass on this Jetson."
  echo "  Reflash with docs/reflash-jetpack6-nvme.md, then run:  sudo ./install.sh HYDRA-1"
  verdict=1
fi
echo
echo "  Full log: $LOG   (send this file if you want a second opinion)"
exit "$verdict"
