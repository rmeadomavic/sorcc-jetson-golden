#!/bin/bash
set -e
cd ~
if [ ! -d ~/ComfyUI ]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI ~/ComfyUI 2>&1 | tail -2
else echo "ComfyUI already cloned @ $(git -C ~/ComfyUI rev-parse --short HEAD)"; fi
python3 -m venv ~/venvs/comfyui
source ~/venvs/comfyui/bin/activate
python -m pip install --upgrade pip -q
echo "=== torch (cached) ==="
pip install torch torchvision --index-url https://pypi.jetson-ai-lab.io/jp7/cu130 \
  --extra-index-url https://pypi.org/simple -q 2>&1 | tail -1
echo "=== ComfyUI requirements (minus torch*) ==="
grep -viE "^torch($|[=<>~ ])|^torchvision|^torchaudio" ~/ComfyUI/requirements.txt > /tmp/creqs.txt
pip install -r /tmp/creqs.txt -q 2>&1 | tail -4
echo "=== sanity ==="
python -c "import torch; print('comfy torch', torch.__version__, 'cuda', torch.cuda.is_available())"
mkdir -p ~/ComfyUI/models/checkpoints ~/ComfyUI/models/loras ~/ComfyUI/output ~/ComfyUI/user/default/workflows
echo DONE
