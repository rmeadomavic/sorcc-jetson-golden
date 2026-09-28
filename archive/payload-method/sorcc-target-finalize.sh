#!/usr/bin/env bash
# Finalize a clean SORCC Jetson after verified artifacts have been staged from the golden box.
# Usage: sudo ./sorcc-target-finalize.sh <linux-user> <tak-callsign>
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }
TARGET_USER="${1:?linux user required}"
CALLSIGN="${2:?TAK callsign required}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
STAGE="$TARGET_HOME/sorcc-stage"
SYSTEMCTL="$(command -v systemctl)"

[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || { echo "Unknown target user: $TARGET_USER" >&2; exit 2; }
for required in \
  "$STAGE/comfyui/models/checkpoints/v1-5-pruned-emaonly-fp16.safetensors" \
  "$STAGE/hydra/models/yolov8n.pt" \
  "$STAGE/hydra/config.ini" \
  "$STAGE/sorcc_launcher.py" \
  "$STAGE/sorcc-jetson-smoke-test.sh" \
  "$STAGE/ollama/ollama" \
  "$STAGE/ollama/lib/llama-server" \
  "$STAGE/ollama/models/manifests/registry.ollama.ai/library/qwen3/4b-instruct" \
  "$STAGE/sorcc-wallpaper.png"; do
  [[ -e "$required" ]] || { echo "Missing staged artifact: $required" >&2; exit 3; }
done

docker image inspect comfyui-sorcc:latest >/dev/null
docker image inspect 'ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d' >/dev/null

# Application payload.
install -d -m 0755 /opt/sorcc /opt/sorcc/comfyui /opt/sorcc/hydra
rsync -a "$STAGE/comfyui/" /opt/sorcc/comfyui/
rsync -a "$STAGE/hydra/" /opt/sorcc/hydra/
install -m 0755 "$STAGE/sorcc_launcher.py" /opt/sorcc/sorcc_launcher.py
install -m 0755 "$STAGE/sorcc-jetson-smoke-test.sh" /opt/sorcc/sorcc-jetson-smoke-test.sh
chown -R "$TARGET_USER:$TARGET_USER" /opt/sorcc/comfyui
chown -R root:root /opt/sorcc/hydra /opt/sorcc/sorcc_launcher.py /opt/sorcc/sorcc-jetson-smoke-test.sh
chmod 0644 /opt/sorcc/hydra/config.ini

# Per-unit Hydra identity. Never inherit the source token.
HYDRA_TOKEN="$(openssl rand -hex 32)"
sed -i -E "s/^api_token[[:space:]]*=.*/api_token = $HYDRA_TOKEN/" /opt/sorcc/hydra/config.ini
sed -i -E "s/^callsign[[:space:]]*=.*/callsign = $CALLSIGN/" /opt/sorcc/hydra/config.ini
sed -i -E '/^\[camera\]/,/^\[/{s/^source_type[[:space:]]*=.*/source_type = auto/;s/^source[[:space:]]*=.*/source = auto/}' /opt/sorcc/hydra/config.ini

# The staging tree is reusable, but it must not retain the source unit's identity.
sed -i -E 's/^api_token[[:space:]]*=.*/api_token = GENERATED_DURING_FINALIZE/' "$STAGE/hydra/config.ini"
sed -i -E 's/^callsign[[:space:]]*=.*/callsign = SET_DURING_FINALIZE/' "$STAGE/hydra/config.ini"

# Offline Ollama runtime and only the locked qwen3:4b-instruct model.
# Swapped from llama3.2:3b on 2026-08-03: the Meta AUP prohibits military use.
# Never stage the plain qwen3:4b alias; it resolves to a thinking-only model.
getent group ollama >/dev/null || groupadd --system ollama
id ollama >/dev/null 2>&1 || useradd --system --gid ollama --home-dir /usr/share/ollama --create-home --shell /bin/false ollama
install -m 0755 "$STAGE/ollama/ollama" /usr/local/bin/ollama
install -d -m 0755 /usr/local/lib/ollama
rsync -a "$STAGE/ollama/lib/" /usr/local/lib/ollama/
chown -R root:root /usr/local/lib/ollama
install -d -o ollama -g ollama -m 0750 /usr/share/ollama/.ollama/models
rsync -a "$STAGE/ollama/models/" /usr/share/ollama/.ollama/models/
chown -R ollama:ollama /usr/share/ollama

cat >/etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

[Install]
WantedBy=default.target
EOF
install -d -m 0755 /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="CUDA_VISIBLE_DEVICES="
Environment="OLLAMA_CONTEXT_LENGTH=4096"
EOF

cat >/etc/systemd/system/sorcc-launcher.service <<EOF
[Unit]
Description=SORCC AI Kit Launcher (student front door, :8090)
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/sorcc/sorcc_launcher.py
Restart=always
RestartSec=3
User=$TARGET_USER
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/comfyui.service <<'EOF'
[Unit]
Description=ComfyUI (SORCC AI Kit - Imagery)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker rm -f comfyui
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=/usr/bin/docker run --rm --name comfyui --runtime nvidia --network host -v /opt/sorcc/comfyui/models:/opt/ComfyUI/models -v /opt/sorcc/comfyui/output:/opt/ComfyUI/output -v /opt/sorcc/comfyui/input:/opt/ComfyUI/input -v /opt/sorcc/comfyui/user:/opt/ComfyUI/user -v /opt/sorcc/comfyui/workflows/SORCC-START-HERE.json:/opt/ComfyUI/user/default/workflows/SORCC-START-HERE.json:ro -v /opt/sorcc/comfyui/workflows/SORCC-QUALITY-20-STEP.json:/opt/ComfyUI/user/default/workflows/SORCC-QUALITY-20-STEP.json:ro -v /opt/sorcc/comfyui/workflows/SORCC-cheat-sheet.json:/opt/ComfyUI/user/default/workflows/SORCC-cheat-sheet.json:ro -v /opt/sorcc/comfyui/custom_nodes/sorcc_student:/opt/ComfyUI/custom_nodes/sorcc_student:ro comfyui-sorcc:latest python3 main.py --listen 0.0.0.0 --port 8188 --disable-all-custom-nodes --whitelist-custom-nodes sorcc_student --cpu-vae --lowvram --preview-method none
ExecStop=/usr/bin/docker stop -t 10 comfyui
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/hydra-detect.service <<'EOF'
[Unit]
Description=Hydra Detect (SORCC AI Kit - Detection)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker rm -f hydra-detect
ExecStartPre=/bin/sync
ExecStartPre=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/vm/compact_memory'
ExecStart=/usr/bin/docker run --rm --name hydra-detect --runtime nvidia --network host --privileged -v /dev:/dev -v /opt/sorcc/hydra:/config -v /opt/sorcc/hydra/models:/data/models ghcr.io/rmeadomavic/hydra-detect@sha256:8b820cbe5edbb033c2633de67b43f6c1ad576785a27a05b4b4221b059451855d python3 -m hydra_detect --config /config/config.ini
ExecStop=/usr/bin/docker stop -t 10 hydra-detect
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/sudoers.d/sorcc-ai <<EOF
$TARGET_USER ALL=(root) NOPASSWD: $SYSTEMCTL start ollama, $SYSTEMCTL stop ollama, $SYSTEMCTL reset-failed ollama, $SYSTEMCTL start comfyui, $SYSTEMCTL stop comfyui, $SYSTEMCTL reset-failed comfyui, $SYSTEMCTL start hydra-detect, $SYSTEMCTL stop hydra-detect, $SYSTEMCTL reset-failed hydra-detect
EOF
chmod 0440 /etc/sudoers.d/sorcc-ai
visudo -cf /etc/sudoers.d/sorcc-ai

# Student desktop treatment.
[[ -x /snap/bin/chromium ]] || { echo "Chromium snap is required for the student launcher." >&2; exit 3; }
install -d -o "$TARGET_USER" -g "$TARGET_USER" \
  "$TARGET_HOME/Desktop" "$TARGET_HOME/Pictures" \
  "$TARGET_HOME/.config" "$TARGET_HOME/.local/share/applications"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 0644 "$STAGE/sorcc-wallpaper.png" "$TARGET_HOME/Pictures/sorcc-wallpaper.png"
rm -f "$TARGET_HOME/.local/share/applications/claude-code-url-handler.desktop"
cat >"$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Chromium Web Browser
Exec=/snap/bin/chromium --no-first-run --no-default-browser-check %U
Terminal=false
Icon=chromium
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
NoDisplay=true
EOF
cat >"$TARGET_HOME/.config/mimeapps.list" <<'EOF'
[Default Applications]
text/html=sorcc-chromium.desktop
x-scheme-handler/http=sorcc-chromium.desktop
x-scheme-handler/https=sorcc-chromium.desktop
EOF
cat >"$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SORCC AI Kit
Comment=Open the offline Language, Imagery, and Detection tools
Exec=xdg-open http://127.0.0.1:8090/
Icon=applications-science
Terminal=false
Categories=Education;
StartupNotify=true
EOF
cp "$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"
chown "$TARGET_USER:$TARGET_USER" \
  "$TARGET_HOME/.config/mimeapps.list" \
  "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop" \
  "$TARGET_HOME/.local/share/applications/SORCC-AI-Kit.desktop" \
  "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"
chmod 0644 "$TARGET_HOME/.config/mimeapps.list" "$TARGET_HOME/.local/share/applications/sorcc-chromium.desktop"
chmod 0755 "$TARGET_HOME/Desktop/SORCC-AI-Kit.desktop"

PIC="file://$TARGET_HOME/Pictures/sorcc-wallpaper.png"
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" dbus-run-session -- bash -c '
  gsettings set org.gnome.desktop.background picture-uri "'"$PIC"'"
  gsettings set org.gnome.desktop.background picture-uri-dark "'"$PIC"'"
  gsettings set org.gnome.desktop.background picture-options centered
  gsettings set org.gnome.desktop.background color-shading-type solid
  gsettings set org.gnome.desktop.background primary-color "#000000"
  gsettings set org.gnome.desktop.background secondary-color "#000000"
  gio set "'"$TARGET_HOME"'/Desktop/SORCC-AI-Kit.desktop" metadata::trusted true || true
' || true

# SD-safe logging and Super power mode.
install -d -m 0755 /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/sorcc-volatile.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=128M
EOF
nvpmodel -m 2

systemctl daemon-reload
systemctl enable --now docker sorcc-launcher
systemctl disable ollama comfyui hydra-detect 2>/dev/null || true
systemctl stop ollama comfyui hydra-detect 2>/dev/null || true
systemctl restart systemd-journald
sleep 3

systemctl is-active sorcc-launcher
curl -fsS http://127.0.0.1:8090/status
printf '\nFINALIZE_OK user=%s callsign=%s token_sha256=%s\n' \
  "$TARGET_USER" "$CALLSIGN" "$(printf %s "$HYDRA_TOKEN" | sha256sum | cut -d' ' -f1)"
