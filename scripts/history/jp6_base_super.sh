#!/bin/bash
# JP6.2.2 base prep + REAL Super enable. Run first thing after a fresh 6.2.2 flash.
# Proves the 1020 MHz GPU clock that JP7.2 could not deliver.
set -e
PW=sorcc
S(){ echo "$PW" | sudo -S -p '' "$@"; }

echo "=== L4T / JetPack version (want R36.x = JP6) ==="
head -1 /etc/nv_tegra_release
cat /etc/nv_boot_control.conf | grep -E "TNSPEC" || true

echo "=== enable Super: MAXN_SUPER (mode 2) + pin clocks ==="
S nvpmodel -m 2 --force || S nvpmodel -m 0 --force   # some 6.2 confs put MAXN at 0; verified below
sleep 2
S nvpmodel -q | sed -n '1,3p'
S jetson_clocks

echo "=== GROUND TRUTH: GPU should now reach 1020 MHz (was 624 on JP7.2) ==="
echo -n "GPU available_frequencies: "; cat /sys/devices/platform/17000000.gpu/devfreq/17000000.gpu/available_frequencies
echo -n "GPU max_freq: "; cat /sys/devices/platform/17000000.gpu/devfreq/17000000.gpu/max_freq
echo -n "CPU max: "; cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies | tr ' ' '\n' | sort -n | tail -1
echo -n "EMC max: "; S cat /sys/kernel/debug/bpmp/debug/clk/emc/max_rate 2>/dev/null || echo "n/a"

echo "=== 16 GB swap (8 GB box, Docker + models) ==="
if ! swapon --show | grep -q /swapfile; then
  S fallocate -l 16G /swapfile
  S chmod 600 /swapfile
  S mkswap /swapfile
  S swapon /swapfile
  echo '/swapfile none swap sw 0 0' | S tee -a /etc/fstab
fi
free -h | sed -n '2,3p'

echo "=== docker group + verify nvidia runtime (JP6 golden path) ==="
S usermod -aG docker "$USER" || true
docker info 2>/dev/null | grep -iE "Runtimes|nvidia" || S docker info | grep -iE "Runtimes|nvidia"

echo "=== quick GPU-in-container smoke (JP6 container DOES get GPU, unlike JP7) ==="
S docker run --rm --runtime nvidia dustynv/l4t-pytorch:r36.4.0 \
  python3 -c "import torch;print('cuda',torch.cuda.is_available(),'dev',torch.cuda.get_device_name(0))" 2>&1 | tail -3 || \
  echo "NOTE: pull dustynv/l4t-pytorch:r36.4.0 first (internet needed)"

echo JP6_BASE_SUPER_DONE
