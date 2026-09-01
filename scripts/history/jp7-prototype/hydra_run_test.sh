#!/bin/bash
source ~/venvs/hydra/bin/activate
cd ~/Hydra
pip install -q "pydeprecate<0.10" 2>&1 | tail -1 || true
# scope-correct: TAK output dark on student image
sed -i '/^\[tak\]/,/^\[/{s/^enabled = .*/enabled = false/}' config.ini
pkill -f hydra_detect 2>/dev/null; sleep 1
echo "=== launch Hydra (UGV, file source, OBSERVE) ==="
nohup python -m hydra_detect --camera-source output_data/test.mp4 --vehicle ugv > ~/hydra-run.log 2>&1 &
HPID=$!
echo "pid $HPID; waiting for :8080 health..."
UP=0
for i in $(seq 1 50); do
  if curl -s -o /dev/null http://localhost:8080/api/health 2>/dev/null; then UP=1; echo "dashboard UP after ~${i}s"; break; fi
  sleep 1
done
if [ "$UP" = 0 ]; then echo "NOT UP — log:"; tail -30 ~/hydra-run.log; kill $HPID 2>/dev/null; exit 1; fi
echo "=== /api/health ==="; curl -s http://localhost:8080/api/health | python3 -m json.tool 2>/dev/null | head -25
echo "=== let it process 10s ==="; sleep 10
echo "=== /api/stats ==="; curl -s http://localhost:8080/api/stats | python3 -m json.tool 2>/dev/null | head -50
echo "=== /api/detections (if present) ==="; curl -s http://localhost:8080/api/detections 2>/dev/null | head -c 600; echo
echo "=== startup log (key lines) ==="; grep -iE "YOLO|model|Camera|Web UI|vehicle|profile|FPS|detect|error|traceback|warn" ~/hydra-run.log | head -25
echo "=== PID still alive? ==="; kill -0 $HPID 2>/dev/null && echo "RUNNING pid $HPID" || echo "EXITED (check log)"
echo "HPID=$HPID"
echo DONE
