#!/bin/bash
# Kill Hydra (box-local, reliable), wait for ComfyUI install, download models.
pkill -9 -f hydra_detect 2>/dev/null && echo "hydra killed" || echo "hydra not running"
CK=~/ComfyUI/models/checkpoints
LORA=~/ComfyUI/models/loras
mkdir -p "$CK" "$LORA"
echo "=== waiting for ComfyUI install to finish ==="
for i in $(seq 1 96); do grep -qE "^DONE" ~/comfyui-install.log 2>/dev/null && { echo "install done"; break; }; sleep 5; done
echo "=== downloading models (wget -c resumable) ==="
dl(){ echo ">> fetching $(basename "$2")"; wget -c -q -O "$2" "$1" && echo "OK $(du -h "$2"|cut -f1) $(basename "$2")" || echo "FAIL $(basename "$2")"; }
dl "https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors" "$CK/v1-5-pruned-emaonly.safetensors"
dl "https://huggingface.co/latent-consistency/lcm-lora-sdv1-5/resolve/main/pytorch_lora_weights.safetensors" "$LORA/lcm-lora-sdv15.safetensors"
dl "https://huggingface.co/Lykon/DreamShaper/resolve/main/DreamShaper_8_pruned.safetensors" "$CK/DreamShaper_8_pruned.safetensors"
echo "=== inventory ==="
du -h "$CK"/*.safetensors "$LORA"/*.safetensors 2>/dev/null
echo MODELS_DONE
