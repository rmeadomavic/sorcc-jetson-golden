#!/bin/bash
# Deploy the SORCC AI launcher + native systemd units + sudoers + desktop icon.
# Runs on sorcc1 as user sorcc1.
PW=sorcc
S(){ echo "$PW" | sudo -S -p '' "$@"; }
U=sorcc1; HD=/home/$U; SC=$(command -v systemctl)

# Hydra camera -> bench test video (student kits with a USB camera set source=auto/0)
sed -i "/^\[camera\]/,/^\[/{s#^source = .*#source = output_data/test.mp4#}" $HD/Hydra/config.ini

# --- unit files (written as user so \$HD expands right, then installed) ---
cat > /tmp/hydra.service <<EOF
[Unit]
Description=Hydra Detect (SORCC detection payload)
After=network-online.target
[Service]
User=$U
WorkingDirectory=$HD/Hydra
ExecStart=$HD/venvs/hydra/bin/python -m hydra_detect --config config.ini --vehicle ugv
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
cat > /tmp/comfyui.service <<EOF
[Unit]
Description=ComfyUI (SORCC image generation)
After=network-online.target
[Service]
User=$U
WorkingDirectory=$HD/ComfyUI
ExecStart=$HD/venvs/comfyui/bin/python main.py --listen 0.0.0.0 --port 8188
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
cat > /tmp/sorcc-launcher.service <<EOF
[Unit]
Description=SORCC AI Launcher (dummy-proof front door)
After=network-online.target
[Service]
User=$U
ExecStart=/usr/bin/python3 $HD/sorcc_launcher.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
cat > /tmp/sorcc-ai.sudoers <<EOF
$U ALL=(root) NOPASSWD: $SC start ollama, $SC stop ollama, $SC restart ollama, $SC reset-failed ollama, $SC start comfyui, $SC stop comfyui, $SC restart comfyui, $SC reset-failed comfyui, $SC start hydra, $SC stop hydra, $SC restart hydra, $SC reset-failed hydra, $SC start hydra-detect, $SC stop hydra-detect, $SC restart hydra-detect, $SC reset-failed hydra-detect
EOF

S cp /tmp/hydra.service /tmp/comfyui.service /tmp/sorcc-launcher.service /etc/systemd/system/
S cp /tmp/sorcc-ai.sudoers /etc/sudoers.d/sorcc-ai
S chmod 440 /etc/sudoers.d/sorcc-ai
echo -n "sudoers valid: "; S visudo -cf /etc/sudoers.d/sorcc-ai

# desktop icon (menu + Desktop)
mkdir -p $HD/.local/share/applications $HD/Desktop
cat > $HD/.local/share/applications/SORCC-AI.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=SORCC AI Kit
Comment=Language, Imagery, Detection - one tool at a time
Exec=xdg-open http://localhost:8090/
Icon=applications-science
Terminal=false
Categories=Education;
EOF
cp $HD/.local/share/applications/SORCC-AI.desktop $HD/Desktop/
chmod +x $HD/Desktop/SORCC-AI.desktop
gio set $HD/Desktop/SORCC-AI.desktop metadata::trusted true 2>/dev/null || true

# enable launcher always-on; tools start on demand (one-tool-at-a-time)
S $SC daemon-reload
S $SC enable --now sorcc-launcher
S $SC stop hydra comfyui 2>/dev/null
S $SC disable hydra comfyui 2>/dev/null
sleep 2
echo -n "launcher active: "; S $SC is-active sorcc-launcher
curl -s -o /dev/null -w "launcher HTTP %{http_code}\n" http://localhost:8090/ 2>/dev/null
echo "=== launcher /status ==="; curl -s http://localhost:8090/status 2>/dev/null
echo; echo DEPLOY_DONE
