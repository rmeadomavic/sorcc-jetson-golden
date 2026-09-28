# ComfyUI image for the SORCC AI Kit ("Imagery").
#
# Target: Jetson Orin Nano on JetPack 6 (L4T R36.x, CUDA 12.6). This image does NOT
# work on JetPack 7: its CUDA 12.6 runtime cannot talk to the JetPack 7 driver.
#
# install.sh builds it on the Jetson itself:
#   docker build -t comfyui-sorcc:latest comfyui/
#
# Base: dustynv/pytorch 2.7-r36.4.0 = Ubuntu 22.04, Python 3.10 (/opt/venv),
# CUDA 12.6, cuDNN 9.3, and PyTorch 2.7.0 / torchvision 0.22.0 / torchaudio 2.7.0
# compiled for the Orin GPU (sm_87). Pinned by digest so every kit gets the same bits.
FROM dustynv/pytorch:2.7-r36.4.0@sha256:8c18f5a68d17dcff25201d075e026c29c195886a999aedb651398617f9d3436c

# The base image points pip at a retired Jetson mirror. Use PyPI.
ENV PIP_INDEX_URL=https://pypi.org/simple \
    PIP_EXTRA_INDEX_URL= \
    PIP_TRUSTED_HOST= \
    PIP_VERBOSE=0 \
    PIP_NO_CACHE_DIR=1

ARG COMFYUI_VERSION=v0.19.3
ARG COMFYUI_COMMIT=3086026401180c9216bcb6ace442a4e3587d2c66

RUN git clone --depth 1 --branch "${COMFYUI_VERSION}" https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && test "$(git -C /opt/ComfyUI rev-parse HEAD)" = "${COMFYUI_COMMIT}" \
 && rm -rf /opt/ComfyUI/.git

WORKDIR /opt/ComfyUI

# --no-deps installs exactly the locked set and never touches the Jetson torch build.
COPY requirements.lock /tmp/requirements.lock
RUN pip3 install --no-deps -r /tmp/requirements.lock \
 && python3 -c "import torch, torchvision, torchaudio; \
assert torch.__version__.startswith('2.7'), torch.__version__; \
assert torch.version.cuda, 'torch was replaced by a CPU-only build'; \
print('torch', torch.__version__, 'cuda', torch.version.cuda)" \
 && python3 -c "import aiohttp, alembic, av, comfy_aimdo, einops, kornia, safetensors, spandrel, sqlalchemy, torchsde, transformers; print('imports ok')" \
 && grep -q '__version__ = "0.19.3"' comfyui_version.py

EXPOSE 8188
# The systemd unit (comfyui.service) supplies the real command line and flags.
CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
