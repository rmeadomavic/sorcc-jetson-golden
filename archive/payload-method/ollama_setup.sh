#!/bin/bash
# Clean Ollama (re)install + pull qwen3:4b-instruct (NEVER plain qwen3:4b - thinking alias). Run AFTER the big docker pull
# so the two large downloads don't contend and reset the connection.
PW=sorcc
echo "=== (re)install ollama as root ==="
echo "$PW" | sudo -S -p '' bash -c 'curl -fsSL https://ollama.com/install.sh | sh' 2>&1 | tail -6
echo "=== enable + start service ==="
echo "$PW" | sudo -S -p '' systemctl enable --now ollama 2>&1
sleep 3
echo "=== version + service ==="
ollama --version 2>&1 | head -1
echo "$PW" | sudo -S -p '' systemctl is-active ollama
echo "=== pull qwen3:4b-instruct ==="
ollama pull qwen3:4b-instruct 2>&1 | tail -4
echo "=== models ==="
ollama list
echo DONE
