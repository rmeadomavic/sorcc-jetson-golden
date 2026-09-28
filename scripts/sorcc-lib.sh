# Shared helpers for install.sh and scripts/jetpack7-test.sh. Source it; do not run it.
# The caller sets REPO (this repo's folder), SORCC (/opt/sorcc), and LOG before sourcing.
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then G=$'\e[1;32m' Y=$'\e[1;33m' R=$'\e[1;31m' N=$'\e[0m'; else G='' Y='' R='' N=''; fi
STEP=0
STEP_NAME="starting"
WARNINGS=()
step() { STEP=$((STEP + 1)); STEP_NAME="$*"; printf '\n%s==> [%d/%d] %s%s\n' "$G" "$STEP" "$TOTAL_STEPS" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s    WARNING: %s%s\n' "$Y" "$*" "$N"; WARNINGS+=("$*"); }
die() {
  printf '\n%sSTOPPED during step %d (%s):%s\n' "$R" "$STEP" "$STEP_NAME" "$N" >&2
  printf '  %s\n' "$@" >&2
  printf '\nFix the problem above, then run the same command again. Finished steps are skipped.\n' >&2
  printf 'Full log: %s\n' "$LOG" >&2
  exit 1
}

retry() {
  local attempt=1
  until "$@"; do
    if (( attempt >= 4 )); then return 1; fi
    printf '%s    attempt %d failed, retrying in %ds: %s%s\n' "$Y" "$attempt" $((attempt * 15)) "$*" "$N"
    sleep $((attempt * 15))
    attempt=$((attempt + 1))
  done
}

# Download URL to DEST and verify its size and SHA-256. Resumes partial downloads.
# A verified file is recorded under $SORCC/.verified so re-runs skip re-hashing it.
fetch() {
  local url="$1" dest="$2" size="$3" sha="$4" part="$2.part" have
  local mark="$SORCC/.verified/${dest##*/}.sha256"
  if [[ -f "$dest" && "$(stat -c %s "$dest")" == "$size" && "$(cat "$mark" 2>/dev/null || true)" == "$sha" ]]; then
    info "already have $(basename "$dest")"
    return 0
  fi
  install -d "$(dirname "$dest")"
  if [[ -f "$dest" && "$(stat -c %s "$dest")" == "$size" ]]; then
    mv -f "$dest" "$part"   # right size but not verified yet: check it instead of downloading again
  fi
  have="$(stat -c %s "$part" 2>/dev/null || echo 0)"
  if (( have > size )); then rm -f "$part"; have=0; fi
  if (( have < size )); then
    info "downloading $(basename "$dest") ($((size / 1000000)) MB)"
    retry curl -fL --retry 5 --retry-delay 10 --connect-timeout 30 -C - --progress-bar -o "$part" "$url" \
      || die "Download failed: $url" "Check the internet connection, then re-run. The download resumes where it stopped."
  fi
  info "checking $(basename "$dest")"
  if [[ "$(stat -c %s "$part")" != "$size" ]] || [[ "$(sha256sum "$part" | cut -d' ' -f1)" != "$sha" ]]; then
    rm -f "$part"
    die "Downloaded file is damaged or has changed upstream: $(basename "$dest")" \
      "Source: $url" "The partial file was deleted. Re-run to download it again."
  fi
  mv -f "$part" "$dest"
  install -d "$SORCC/.verified"
  printf '%s\n' "$sha" >"$mark"
}

# Download every model in comfyui/models.txt whose path matches the optional regex.
fetch_comfy_models() {
  local filter="${1:-.}" rel size sha url
  while read -r rel size sha url; do
    [[ -z "$rel" || "$rel" == \#* ]] && continue
    [[ "$rel" =~ $filter ]] || continue
    fetch "$url" "$SORCC/comfyui/models/$rel" "$size" "$sha"
  done <"$REPO/comfyui/models.txt"
}

# Class workflows, the START HERE helper node, and first-run settings.
install_comfy_files() {
  local c="$SORCC/comfyui"
  install -d -m 0755 "$c" "$c/models/checkpoints" "$c/models/loras" "$c/input" "$c/output" \
    "$c/user/default/workflows" "$c/workflows" "$c/custom_nodes"
  install -m 0644 "$REPO"/comfyui/workflows/*.json "$c/workflows/"
  rsync -a --delete "$REPO/comfyui/sorcc_student/" "$c/custom_nodes/sorcc_student/"
  [[ -f "$c/user/default/comfy.settings.json" ]] || install -m 0644 "$REPO/comfyui/comfy.settings.json" "$c/user/default/comfy.settings.json"
  if [[ "${PLATFORM:-}" == jp7 ]]; then
    # No container bind mounts on JetPack 7: ComfyUI reads the workflows from its user folder.
    install -m 0644 "$REPO"/comfyui/workflows/*.json "$c/user/default/workflows/"
  fi
}

# ---------------------------------------------------------------------------
# JetPack 7 (no Docker): one Python environment and pinned app sources
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # used by install.sh and scripts/jetpack7-test.sh
PYTORCH_INDEX="https://download.pytorch.org/whl/cu130"
# shellcheck disable=SC2034
COMFYUI_COMMIT="3086026401180c9216bcb6ace442a4e3587d2c66"   # ComfyUI v0.19.3
# shellcheck disable=SC2034
HYDRA_COMMIT="405eaf8b5b12f6c4a5e186b2c8272bda67b19a6c"     # the commit the pinned Hydra image was built from
VENV="$SORCC/venv"

# Fetch OWNER/REPO at COMMIT (git, no history) into $SORCC/app/NAME (skipped when already there).
jp7_app_source() {
  local name="$1" repo="$2" commit="$3" dest="$SORCC/app/$1" tmp
  if [[ "$(cat "$dest/.sorcc-commit" 2>/dev/null || true)" == "$commit" ]]; then
    info "$name source already at ${commit:0:7}"
    return 0
  fi
  info "Downloading $name source (${commit:0:7})"
  tmp="$(mktemp -d)"
  git init -q "$tmp/src"
  retry git -C "$tmp/src" fetch -q --depth 1 "https://github.com/$repo.git" "$commit" \
    || die "Could not download $repo from GitHub."
  git -C "$tmp/src" checkout -q FETCH_HEAD
  rm -rf "$tmp/src/.git"
  install -d "$SORCC/app"
  rm -rf "$dest"
  mv "$tmp/src" "$dest"
  printf '%s\n' "$commit" >"$dest/.sorcc-commit"
  rm -rf "$tmp"
}

# Build $SORCC/venv from jetpack7/requirements.lock (skipped when already built from this lock).
jp7_python_env() {
  local lock="$REPO/jetpack7/requirements.lock" want
  want="$(sha256sum "$lock" | cut -d' ' -f1)"
  if [[ -x "$VENV/bin/python" && "$(cat "$VENV/.sorcc-lock" 2>/dev/null || true)" == "$want" ]]; then
    info "Python environment is up to date"
    return 0
  fi
  info "Building the Python environment (downloads about 3 GB; 10 to 20 minutes)"
  python3 -m venv --clear "$VENV" || die "Could not create $VENV." "Install the venv module: sudo apt-get install python3-venv"
  retry "$VENV/bin/pip" install --no-deps --progress-bar off \
    --index-url https://pypi.org/simple --extra-index-url "$PYTORCH_INDEX" -r "$lock" \
    || die "Installing the Python packages failed. Scroll up for the first error." \
      "If it was a network error, just re-run; finished downloads are reused."
  printf '%s\n' "$want" >"$VENV/.sorcc-lock"
}

# Prove PyTorch reaches the GPU and computes the same answers as the CPU, in fp32 and fp16.
# Blank Stable Diffusion images usually start as wrong or NaN GPU math, so check the math.
jp7_gpu_check() {
  "$VENV/bin/python" - <<'PY'
import sys, torch
if not torch.cuda.is_available():
    print("FAIL: PyTorch cannot see the GPU (torch.cuda.is_available() is False)")
    sys.exit(1)
torch.backends.cudnn.allow_tf32 = False   # compare exact fp32, not TF32
torch.backends.cuda.matmul.allow_tf32 = False
name = torch.cuda.get_device_name(0)
cap = torch.cuda.get_device_capability(0)
torch.manual_seed(0)
a, b = torch.randn(512, 512), torch.randn(512, 512)
x, w = torch.randn(1, 64, 64, 64), torch.randn(64, 64, 3, 3)
worst = 0.0
for dtype, tol in ((torch.float32, 1e-3), (torch.float16, 2e-2)):
    ref_mm = a.to(dtype).float() @ b.to(dtype).float()
    ref_cv = torch.nn.functional.conv2d(x.to(dtype).float(), w.to(dtype).float(), padding=1)
    gpu_mm = (a.cuda().to(dtype) @ b.cuda().to(dtype)).float().cpu()
    gpu_cv = torch.nn.functional.conv2d(x.cuda().to(dtype), w.cuda().to(dtype), padding=1).float().cpu()
    for label, ref, got in (("matmul", ref_mm, gpu_mm), ("conv2d", ref_cv, gpu_cv)):
        if not torch.isfinite(got).all():
            print(f"FAIL: GPU {label} in {dtype} returned NaN or Inf")
            sys.exit(1)
        err = ((got - ref).norm() / ref.norm()).item()
        worst = max(worst, err)
        if err > tol:
            print(f"FAIL: GPU {label} in {dtype} is wrong (relative error {err:.2e})")
            sys.exit(1)
print(f"OK: {name} (sm_{cap[0]}{cap[1]}), torch {torch.__version__}, "
      f"GPU math matches CPU (worst relative error {worst:.1e})")
PY
}
