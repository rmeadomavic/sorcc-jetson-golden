#!/bin/bash
# Ollama: ensure working install, pull llama3.2:3b, confirm GPU, benchmark tok/s.
PW=sorcc
S(){ echo "$PW" | sudo -S -p '' "$@"; }

if ! ollama --version >/dev/null 2>&1; then
  echo "=== ollama binary missing/broken — reinstalling ==="
  S bash -c 'curl -fsSL https://ollama.com/install.sh | sh' 2>&1 | tail -5
fi
S systemctl enable --now ollama >/dev/null 2>&1
sleep 3
echo -n "ollama version: "; ollama --version 2>&1 | head -1
echo -n "service: "; S systemctl is-active ollama

echo "=== pull llama3.2:3b ==="
ollama pull llama3.2:3b 2>&1 | tail -3
ollama list

echo "=== warm-up (loads model into VRAM) ==="
ollama run llama3.2:3b "Say READY." >/dev/null 2>&1
echo -n "processor split: "; ollama ps | awk 'NR==2{print $NF, $(NF-1)}'
ollama ps

echo "=== BENCHMARK 1: PCC/PCI checklist ==="
ollama run llama3.2:3b --verbose "Write a 5-item pre-combat inspection checklist for a ground robot patrol. Terse." 2>&1 | grep -iE "eval rate|eval count|total duration|load duration"

echo "=== BENCHMARK 2: patrol brief summary ==="
ollama run llama3.2:3b --verbose "Summarize in 3 bullets: a UGV scouted a village, found two parked trucks and one armed individual near a building." 2>&1 | grep -iE "eval rate|eval count|total duration"
echo DONE
