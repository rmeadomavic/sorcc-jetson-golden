#!/usr/bin/env bash
# sorcc-jetson-smoke-test.sh - per-kit acceptance test for the SORCC AI Kit image.
#
# Run after flashing and first-boot identity setup, with the USB camera connected:
#   sudo /opt/sorcc/sorcc-jetson-smoke-test.sh
#
# Exercises the same launcher path students use. It enforces one heavy tool at a time,
# verifies the Stop All control,
# requires real Ollama content, requires a successful ComfyUI history record and PNG,
# verifies the camera/detector path, and confirms the Hydra dark-surface configuration.

set -uo pipefail

HYDRA_DIR="${HYDRA_DIR:-/opt/sorcc/hydra}"
COMFY_DIR="${COMFY_DIR:-/opt/sorcc/comfyui}"
LLM_MODEL="${LLM_MODEL:-qwen3:4b-instruct}"
LAUNCHER="${LAUNCHER:-http://127.0.0.1:8090}"
DASH="${DASH:-http://127.0.0.1:8080}"
COMFY="${COMFY:-http://127.0.0.1:8188}"

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

CONFIG="$HYDRA_DIR/config.ini"
PASS=0; FAIL=0; WARN=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
hdr()  { printf '\n== %s ==\n' "$*"; }

cfg() {
  python3 - "$CONFIG" "$1" "$2" <<'PY' 2>/dev/null
import configparser, sys
c = configparser.ConfigParser(inline_comment_prefixes=(';', '#'))
c.read(sys.argv[1])
print(c.get(sys.argv[2], sys.argv[3], fallback=''))
PY
}

start_tool() {
  curl -fsS -X POST "$LAUNCHER/start?tool=$1" >/dev/null
}

wait_url() {
  local url="$1" tries="${2:-90}"
  for _ in $(seq 1 "$tries"); do
    curl -fsS --max-time 3 "$url" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

exclusive() {
  python3 - "$1" <<'PY'
import json, sys, urllib.request
x = json.load(urllib.request.urlopen('http://127.0.0.1:8090/status', timeout=5))
active = [k for k, v in x['services'].items() if v]
print('active=' + ','.join(active))
raise SystemExit(0 if x.get('active') == sys.argv[1] and active == [sys.argv[1]] else 1)
PY
}

echo "SORCC Jetson acceptance: $(hostname)"

hdr "1. Base platform"
if [[ -f /etc/nv_tegra_release ]]; then
  ok "$(head -1 /etc/nv_tegra_release | tr -s ' ')"
else
  bad "missing /etc/nv_tegra_release"
fi
MODE="$(nvpmodel -q 2>/dev/null | grep -i 'Power Mode' | head -1)"
echo "$MODE" | grep -qi MAXN && ok "power mode: $MODE" || bad "power mode is not MAXN: $MODE"
[[ -c /dev/video0 ]] && ok "USB camera node /dev/video0 present" || bad "USB camera node /dev/video0 missing"
[[ -f "$COMFY_DIR/models/checkpoints/v1-5-pruned-emaonly-fp16.safetensors" ]] \
  && ok "SD 1.5 checkpoint present" || bad "SD 1.5 checkpoint missing"
[[ -f "$HYDRA_DIR/models/yolov8n.pt" ]] && ok "offline YOLO weights present" || bad "offline YOLO weights missing"
SHORTCUT="$(find /home -maxdepth 3 -type f -name 'SORCC-AI-Kit.desktop' -perm /111 2>/dev/null | head -1)"
if [[ -n "$SHORTCUT" ]] && grep -q 'http://127.0.0.1:8090/' "$SHORTCUT"; then
  ok "student desktop shortcut present"
else
  bad "student desktop shortcut missing or points at the wrong URL"
fi

hdr "2. Hydra dark surface"
check_false() {
  local v; v="$(cfg "$1" "$2")"
  case "${v,,}" in false|0|no|off|'') ok "[$1].$2 is dark";; *) bad "[$1].$2 is $v";; esac
}
check_false rf_homing enabled
check_false autonomous enabled
check_false servo_tracking enabled
check_false tak listen_commands
DROP="$(cfg drop servo_channel)"
[[ "${DROP:-0}" == 0 ]] && ok "[drop].servo_channel is 0" || bad "[drop].servo_channel is $DROP"

hdr "3. Detection through launcher"
if start_tool detect && wait_url "$DASH/api/health" 120; then
  python3 <<'PY' && ok "camera and detector healthy" || bad "camera or detector unhealthy"
import json, urllib.request
h = json.load(urllib.request.urlopen('http://127.0.0.1:8080/api/health', timeout=5))
s = json.load(urllib.request.urlopen('http://127.0.0.1:8080/api/stats', timeout=5))
print('fps', round(s.get('fps', 0), 1), 'inference_ms', round(s.get('inference_ms', 0), 1))
raise SystemExit(0 if h.get('healthy') and s.get('camera_ok') and s.get('detector') == 'yolo' and s.get('fps', 0) > 1 else 1)
PY
  curl -fsS --max-time 8 "$DASH/stream.jpg" -o /tmp/sorcc-smoke-camera.jpg
  [[ $(stat -c %s /tmp/sorcc-smoke-camera.jpg 2>/dev/null || echo 0) -gt 1024 ]] \
    && ok "live camera JPEG received" || bad "live camera JPEG missing"
  if exclusive detect; then ok "Detection is the only active tool"; else bad "one-tool exclusivity failed"; fi
  DETECTIONS="$(curl -fsS "$DASH/api/stats" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total_detections",0))')"
  [[ "$DETECTIONS" -gt 0 ]] && ok "detector produced a live detection" \
    || warn "no object detected; put a person in frame and confirm box, label, and track ID"
else
  bad "Detection did not become ready"
fi

hdr "4. Language through launcher"
if start_tool chat && wait_url "http://127.0.0.1:11434/api/tags" 120; then
  python3 <<'PY' && ok "streaming Ollama training UI returned content and metrics" || bad "Ollama streaming test failed"
import json, urllib.request
b = json.dumps({'messages':[{'role':'user','content':'Reply with exactly these three words: SORCC LANGUAGE PASS'}]}).encode()
r = urllib.request.Request('http://127.0.0.1:8090/api/chat', data=b, headers={'Content-Type':'application/json'})
reply = ''
done = None
events = []
with urllib.request.urlopen(r, timeout=180) as response:
 for raw in response:
  event = json.loads(raw)
  events.append(event.get('event'))
  if event.get('event') == 'content': reply += event.get('text', '')
  if event.get('event') == 'done': done = event
print(reply)
page = urllib.request.urlopen('http://127.0.0.1:8090/chat', timeout=5).read().decode()
menu = urllib.request.urlopen('http://127.0.0.1:8090/', timeout=5).read().decode()
markers = (
 'Model responses and reasoning traces can be wrong.',
 'Read prompt', 'Output tokens', 'Generation speed',
 "l.textContent='You'", "l.textContent='AI response'",
)
valid = (
 all(k in reply.upper() for k in ('SORCC','LANGUAGE','PASS'))
 and events[:2] == ['start', 'phase'] and events[-1:] == ['done']
 and done and done.get('eval_count', 0) > 0 and done.get('eval_duration', 0) > 0
 and all(marker in page for marker in markers)
 and 'Start with the preset workflow, then compare prompts, checkpoints, and LoRAs.' in menu
 and 'The class configuration observes and reports. It does not act.' in menu
 and "buffer.split('\\n')" in page
 and "box.addEventListener('keydown'" in page
)
raise SystemExit(0 if valid else 1)
PY
  if exclusive chat; then ok "Language is the only active tool"; else bad "one-tool exclusivity failed"; fi
else
  bad "Language did not become ready"
fi

hdr "5. Imagery through launcher"
if start_tool image && wait_url "$COMFY/system_stats" 180; then
  python3 <<'PY' && ok "ComfyUI v0.19.3 student runtime active" || bad "wrong ComfyUI runtime"
import json, urllib.request
x = json.load(urllib.request.urlopen('http://127.0.0.1:8188/system_stats', timeout=5))['system']
print('version', x.get('comfyui_version'), 'pytorch', x.get('pytorch_version'))
a = x.get('argv', [])
required = ('--cpu-vae', '--lowvram', '--preview-method', '--whitelist-custom-nodes')
raise SystemExit(0 if x.get('comfyui_version') == '0.19.3' and all(v in a for v in required) else 1)
PY
  python3 - "$COMFY_DIR/workflows/SORCC-START-HERE.json" "$COMFY_DIR/output" <<'PY' \
    && ok "shipped START HERE workflow produced a PNG" || bad "shipped ComfyUI workflow failed"
import json, os, sys, time, urllib.request
base = 'http://127.0.0.1:8188'
workflow_path, outdir = sys.argv[1:3]
graph = json.load(open(workflow_path))
nodes = {str(n['id']): n for n in graph['nodes']}
w = {
 '1':{'class_type':'CheckpointLoaderSimple','inputs':{'ckpt_name':nodes['1']['widgets_values'][0]}},
 '2':{'class_type':'CLIPSetLastLayer','inputs':{'clip':['1',1],'stop_at_clip_layer':nodes['2']['widgets_values'][0]}},
 '3':{'class_type':'LoraLoader','inputs':{'model':['1',0],'clip':['2',0],'lora_name':nodes['3']['widgets_values'][0],'strength_model':nodes['3']['widgets_values'][1],'strength_clip':nodes['3']['widgets_values'][2]}},
 '4':{'class_type':'CLIPTextEncode','inputs':{'text':nodes['4']['widgets_values'][0],'clip':['3',1]}},
 '5':{'class_type':'CLIPTextEncode','inputs':{'text':nodes['5']['widgets_values'][0],'clip':['3',1]}},
 '6':{'class_type':'EmptyLatentImage','inputs':{'width':nodes['6']['widgets_values'][0],'height':nodes['6']['widgets_values'][1],'batch_size':nodes['6']['widgets_values'][2]}},
 '7':{'class_type':'KSampler','inputs':{'seed':int(time.time()),'steps':nodes['7']['widgets_values'][2],'cfg':nodes['7']['widgets_values'][3],'sampler_name':nodes['7']['widgets_values'][4],'scheduler':nodes['7']['widgets_values'][5],'denoise':nodes['7']['widgets_values'][6],'model':['3',0],'positive':['4',0],'negative':['5',0],'latent_image':['6',0]}},
 '8':{'class_type':'VAEDecode','inputs':{'samples':['7',0],'vae':['1',2]}},
 '9':{'class_type':'SaveImage','inputs':{'filename_prefix':'sorcc_acceptance','images':['8',0]}}}
assert nodes['6']['widgets_values'] == [256, 256, 1]
assert nodes['7']['widgets_values'][2:6] == [4, 1.5, 'lcm', 'sgm_uniform']
r = urllib.request.Request(base+'/prompt', data=json.dumps({'prompt':w}).encode(), headers={'Content-Type':'application/json'})
t = time.time(); pid = json.load(urllib.request.urlopen(r, timeout=30))['prompt_id']
while time.time()-t < 420:
 h = json.load(urllib.request.urlopen(base+'/history/'+pid, timeout=10))
 if pid in h:
  e = h[pid]; status = e.get('status', {})
  if status.get('status_str') != 'success': raise SystemExit(2)
  imgs = [im for node in e.get('outputs', {}).values() for im in node.get('images', [])]
  if not imgs: raise SystemExit(3)
  for im in imgs:
   p = os.path.join(outdir, im.get('subfolder',''), im['filename'])
   if not os.path.isfile(p) or os.path.getsize(p) < 1024: raise SystemExit(4)
   print(p, os.path.getsize(p), 'bytes', round(time.time()-t,1), 'seconds')
  raise SystemExit(0)
 time.sleep(2)
raise SystemExit(5)
PY
  python3 - <<'PY' && ok "student workflows and auto-loader are published" || bad "student workflow publishing failed"
import json, urllib.request
files = json.load(urllib.request.urlopen('http://127.0.0.1:8188/api/userdata?dir=workflows', timeout=5))
required = {'SORCC-START-HERE.json', 'SORCC-QUALITY-20-STEP.json', 'SORCC-cheat-sheet.json'}
assert required.issubset(files), files
r = urllib.request.urlopen('http://127.0.0.1:8188/extensions/sorcc_student/sorcc_default.js', timeout=5)
assert r.status == 200 and b'SORCC.StudentStartWorkflow' in r.read()
PY
  IMAGE_URL="$(curl -fsS -X POST "$LAUNCHER/start?tool=image" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))')"
  [[ "$IMAGE_URL" == *'?sorcc=start' ]] && ok "Imagery launcher requests START HERE workflow" \
    || bad "Imagery launcher does not request START HERE workflow"
  if exclusive image; then ok "Imagery is the only active tool"; else bad "one-tool exclusivity failed"; fi
else
  bad "Imagery did not become ready"
fi

hdr "6. Stop All launcher control"
python3 <<'PY' && ok "Stop All stopped every heavy tool" || bad "Stop All control failed"
import json, urllib.request
r = urllib.request.Request('http://127.0.0.1:8090/stop', method='POST')
x = json.load(urllib.request.urlopen(r, timeout=90))
s = x.get('status', {})
print('active=' + str(s.get('active')), 'services=' + json.dumps(s.get('services', {}), sort_keys=True))
raise SystemExit(0 if x.get('ok') and s.get('active') is None and not any(s.get('services', {}).values()) else 1)
PY
if [[ -z "$(systemctl --failed --no-legend --plain)" ]]; then
  ok "Stop All left no failed systemd units"
else
  systemctl --failed --no-pager
  bad "Stop All left a failed systemd unit"
fi

hdr "7. Leave kit in Detection mode"
if start_tool detect && wait_url "$DASH/api/health" 120 && exclusive detect; then
  ok "Detection restored and other heavy tools stopped"
else
  bad "could not restore Detection mode"
fi

hdr "SUMMARY"
echo "  PASS $PASS  WARN $WARN  FAIL $FAIL"
if [[ $FAIL -eq 0 ]]; then
  echo "  RESULT: software acceptance passed. Complete any manual warning before issue."
  exit 0
fi
echo "  RESULT: NOT READY"
exit 1
