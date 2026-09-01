#!/bin/bash
PW=sorcc
echo "$PW" | sudo -S -p '' systemctl stop comfyui 2>/dev/null
source ~/venvs/comfyui/bin/activate
echo "=== install torchaudio (match torch 2.13.0+cu130) ==="
pip install torchaudio --index-url https://pypi.jetson-ai-lab.io/jp7/cu130 \
  --extra-index-url https://pypi.org/simple 2>&1 | tail -4
echo "=== verify torch stack intact ==="
python -c "import torch, torchaudio; print('torch', torch.__version__, 'audio', torchaudio.__version__, 'cuda', torch.cuda.is_available())"
echo "=== start comfyui service ==="
echo "$PW" | sudo -S -p '' systemctl restart comfyui
UP=0
for i in $(seq 1 90); do curl -s -o /dev/null http://localhost:8188/system_stats 2>/dev/null && { echo "COMFYUI_UP ~$((i*2))s"; UP=1; break; }; sleep 2; done
[ "$UP" = 0 ] && { echo "STILL_NOT_UP"; journalctl -u comfyui --no-pager -n 15; exit 1; }
echo "=== generation benchmark ==="
~/venvs/comfyui/bin/python ~/comfyui_gentest.py 2>&1
echo "=== output pngs ==="
ls -tr ~/ComfyUI/output/*.png 2>/dev/null | tail -5
echo FIX_AND_TEST_DONE
