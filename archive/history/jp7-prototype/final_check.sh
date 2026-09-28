#!/bin/bash
echo "=== switch to chat via launcher (stops comfyui, starts ollama) ==="
curl -s -X POST 'http://localhost:8090/start?tool=chat'; echo
sleep 6
echo "=== launcher /status ==="
curl -s http://localhost:8090/status; echo
echo "=== built-in chat proxy -> ollama ==="
curl -s -X POST http://localhost:8090/api/chat -H 'Content-Type: application/json' \
  -d '{"msg":"In one sentence, what is a pre-combat inspection?"}' | head -c 400; echo
echo "=== FINAL INVENTORY ==="
echo "-- venvs --"; ls ~/venvs 2>/dev/null
echo "-- checkpoints/loras --"; du -h ~/ComfyUI/models/checkpoints/*.safetensors ~/ComfyUI/models/loras/*.safetensors 2>/dev/null
echo "-- ollama --"; ollama list 2>/dev/null
echo "-- unit enable state --"; for u in sorcc-launcher ollama hydra comfyui; do printf "%s: %s/%s\n" "$u" "$(systemctl is-enabled $u 2>/dev/null)" "$(systemctl is-active $u 2>/dev/null)"; done
echo "-- swap/mem --"; free -h | sed -n '2,3p'
echo "-- disk --"; df -h / | tail -1
echo FINAL_CHECK_DONE
