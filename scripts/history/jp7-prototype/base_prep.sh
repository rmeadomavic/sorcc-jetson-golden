#!/bin/bash
# Base prep on sorcc1 (JetPack 7). Idempotent. Runs as user sorcc1; sudo via -S.
PW=sorcc
S(){ echo "$PW" | sudo -S -p '' bash -c "$1" 2>&1; }

echo "== docker group =="
S 'id -nG sorcc1 | tr " " "\n" | grep -qx docker || usermod -aG docker sorcc1'
S 'getent group docker'

echo "== swap 16G =="
if S 'swapon --show' | grep -q /swapfile; then
  echo "swap already present"
else
  S 'fallocate -l 16G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile' | tail -2
  # fallocate can produce a holey file swapon rejects; fall back to dd if needed
  if ! S 'swapon --show' | grep -q /swapfile; then
    echo "fallocate swap failed, retrying with dd (slower)"
    S 'rm -f /swapfile; dd if=/dev/zero of=/swapfile bs=1M count=16384 status=none && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile' | tail -2
  fi
  S 'grep -q /swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab'
fi
S 'swapon --show'

echo "== apt update+install =="
S 'apt-get update -y >/tmp/apt-up.log 2>&1; tail -2 /tmp/apt-up.log'
S 'DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-venv python3-full ffmpeg v4l-utils jq nano git curl wget >/tmp/apt-inst.log 2>&1; tail -3 /tmp/apt-inst.log'

echo "== max clocks (15W ceiling) =="
S 'jetson_clocks' && echo "jetson_clocks applied"

echo "== status =="
free -h | awk 'NR<=3'
echo -n "pip: "; python3 -m pip --version 2>/dev/null || echo MISSING
echo -n "docker (via sg): "; sg docker -c 'docker version --format "{{.Server.Version}}"' 2>/dev/null || echo "sg-docker not yet effective"
echo DONE
