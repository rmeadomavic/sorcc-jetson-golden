#!/bin/bash
set -e
python3 -m venv ~/venvs/hydra
source ~/venvs/hydra/bin/activate
python -m pip install --upgrade pip -q
echo "=== torch+torchvision (cached wheels) ==="
pip install torch torchvision --index-url https://pypi.jetson-ai-lab.io/jp7/cu130 \
  --extra-index-url https://pypi.org/simple -q 2>&1 | tail -2
echo "=== ultralytics+supervision (--no-deps) then remaining reqs ==="
pip install --no-deps ultralytics supervision -q
# exclude ONLY ultralytics/supervision (keep opencv-python-headless — it provides cv2)
grep -vE "^(ultralytics|supervision)\b" ~/Hydra/requirements.txt > /tmp/hreqs.txt
pip install -r /tmp/hreqs.txt -q 2>&1 | tail -3
# ultralytics runtime deps skipped by --no-deps (headless satisfies its cv2 need)
pip install -q polars psutil ultralytics-thop nvidia-ml-py pandas scipy matplotlib tqdm py-cpuinfo defusedxml pyyaml 2>&1 | tail -2
echo "=== import sanity ==="
python -c "import torch,cv2,ultralytics,supervision,fastapi,uvicorn,pymavlink,mgrs,jinja2,requests; print('imports OK | torch',torch.__version__,'| cv2',cv2.__version__,'| ultralytics',ultralytics.__version__)"
echo "=== YOLOv8n GPU inference smoke test ==="
python - <<'PY'
from ultralytics import YOLO
import time, numpy as np
m = YOLO("yolov8n.pt")   # auto-downloads ~6MB
m.to("cuda")
img = (np.random.rand(480,640,3)*255).astype("uint8")
for _ in range(3): m.predict(img, verbose=False, device=0, imgsz=416)  # warmup (sm_87 JIT)
t=time.time(); N=40
for _ in range(N): r=m.predict(img, verbose=False, device=0, imgsz=416)
dt=time.time()-t
print(f"YOLOv8n @416 GPU: {N/dt:.1f} FPS  ({dt/N*1000:.1f} ms/frame)")
print("boxes tensor device:", r[0].boxes.data.device)
PY
echo DONE
