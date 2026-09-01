#!/bin/bash
# Launch ComfyUI server on :8188. Frees GPU first (one-tool-at-a-time).
echo sorcc | sudo -S -p '' systemctl stop ollama 2>/dev/null && echo "ollama stopped (free VRAM)"
pkill -9 -f hydra_detect 2>/dev/null
pkill -f "ComfyUI/main.py" 2>/dev/null; sleep 1
source ~/venvs/comfyui/bin/activate
cd ~/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 > ~/comfyui-serve.log 2>&1 &
echo "comfyui pid $!; waiting for :8188..."
for i in $(seq 1 60); do
  curl -s -o /dev/null http://localhost:8188/system_stats 2>/dev/null && { echo "COMFYUI_UP after ~${i}s"; break; }
  sleep 2
done
tail -8 ~/comfyui-serve.log
