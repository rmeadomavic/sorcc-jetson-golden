#!/bin/bash
# Switch to Imagery via the launcher (stops ollama, starts comfyui), then benchmark.
echo "=== requesting image tool via launcher (one-tool switch) ==="
curl -s -X POST 'http://localhost:8090/start?tool=image' ; echo
echo "=== waiting for ComfyUI :8188 (cold start loads torch) ==="
UP=0
for i in $(seq 1 120); do
  curl -s -o /dev/null http://localhost:8188/system_stats 2>/dev/null && { echo "COMFYUI_UP after ~$((i*2))s"; UP=1; break; }
  sleep 2
done
if [ "$UP" = 0 ]; then echo "COMFYUI_NOT_UP"; tail -20 ~/comfyui-serve.log 2>/dev/null; journalctl -u comfyui --no-pager -n 20 2>/dev/null; exit 1; fi
echo "=== generation benchmark (base SD1.5, then LCM-LoRA) ==="
~/venvs/comfyui/bin/python ~/comfyui_gentest.py 2>&1
echo "=== output files ==="
ls -tr ~/ComfyUI/output/*.png 2>/dev/null | tail -5
echo RUN_AND_TEST_DONE
