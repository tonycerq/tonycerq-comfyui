#!/usr/bin/env bash

set -euo pipefail

# Default environment variables
export MODELS_CONFIG_URL="${MODELS_CONFIG_URL:-https://raw.githubusercontent.com/tonycerq/tonycerq-comfyui/refs/heads/main/models_config.json}"
export SKIP_CUSTOM_NODES_DOWNLOAD="${SKIP_CUSTOM_NODES_DOWNLOAD:-false}"
export SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-true}"
export LOG_PATH="${LOG_PATH:-/notebooks/backend.log}"
export USE_SAGE_ATTENTION="${USE_SAGE_ATTENTION:-false}"
export TORCH_FORCE_WEIGHTS_ONLY_LOAD=1

# CUDA environment configuration
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export CUDA_LAUNCH_BLOCKING=1


export UV_PREFER_BINARY="${UV_PREFER_BINARY:-1}"
export PIP_ONLY_BINARY="${PIP_ONLY_BINARY:-pycairo,rlpycairo}"
export PIP_NO_BUILD_ISOLATION="${PIP_NO_BUILD_ISOLATION:-1}"

# Ensure uv will be on PATH when installed via the official script
export PATH="/opt/venv/bin:${HOME}/.cargo/bin:${PATH}"


readonly WORKSPACE_DIR="/workspace"
readonly COMFY_DIR="${WORKSPACE_DIR}/comfyui"
readonly CUSTOM_NODES_DIR="${COMFY_DIR}/custom_nodes"
readonly LOG_DIR="${WORKSPACE_DIR}/logs"
readonly COMFY_LOG="${LOG_DIR}/comfyui.log"
readonly MODELS_CONFIG_PATH="${WORKSPACE_DIR}/models_config.json"
readonly DASHBOARD_WORKDIR="/notebooks"
readonly DASHBOARD_SCRIPT_PATH="${DASHBOARD_WORKDIR}/web/dashboard.py"
readonly DASHBOARD_MODULE="web.dashboard"
readonly DOWNLOAD_MODELS_SCRIPT="${DASHBOARD_WORKDIR}/download_models.py"
readonly COMFY_MANAGER_CONFIG_URL="https://gist.githubusercontent.com/vjumpkung/b2993de3524b786673552f7de7490b08/raw/b7ae0b4fe0dad5c930ee290f600202f5a6c70fa8/uv_enabled_config.ini"

readonly -a CUSTOM_NODE_REPOS=(
  "https://github.com/ltdrdata/ComfyUI-Manager.git|ComfyUI-Manager"
  "https://github.com/cubiq/ComfyUI_essentials.git|ComfyUI_essentials"
  "https://github.com/kijai/ComfyUI-KJNodes.git|ComfyUI-KJNodes"
  "https://github.com/city96/ComfyUI-GGUF.git|ComfyUI-GGUF"
  "https://github.com/rgthree/rgthree-comfy.git|rgthree-comfy"
  "https://github.com/justUmen/Bjornulf_custom_nodes.git|Bjornulf_custom_nodes"
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git|ComfyUI-Custom-Scripts"
  "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git|ComfyUI-Frame-Interpolation"
)

HAS_INTERNET=0
COMFY_PID=""

log_info() {
    local message=$1
    printf '[INFO] %s\n' "$message" | tee -a "$COMFY_LOG"
}

log_warn() {
    local message=$1
    printf '[WARN] %s\n' "$message" | tee -a "$COMFY_LOG" >&2
}

log_error() {
    local message=$1
    printf '[ERROR] %s\n' "$message" | tee -a "$COMFY_LOG" >&2
}

log_section() {
    local title=$1
    log_info "=========================================================="
    log_info " ${title}"
    log_info "=========================================================="
}

setup_workspace() {
    mkdir -p "$LOG_DIR"
    touch "$COMFY_LOG"
}

clean_log_file() {
    if [[ -s "$COMFY_LOG" ]]; then
        local tmp_file
        tmp_file=$(mktemp)
        awk '!seen[$0]++' "$COMFY_LOG" >"$tmp_file"
        mv "$tmp_file" "$COMFY_LOG"
    fi
}

start_dashboard() {
    if [[ ! -f "$DASHBOARD_SCRIPT_PATH" ]]; then
        log_warn "Dashboard script not found at $DASHBOARD_SCRIPT_PATH; skipping startup."
        return
    fi

    pushd "$DASHBOARD_WORKDIR" >/dev/null
    CUDA_VISIBLE_DEVICES="" nohup python -m "$DASHBOARD_MODULE" &>"$LOG_PATH" &

    popd >/dev/null
    log_info "Started dashboard on port 8189 - monitor at http://localhost:8189"
}

check_internet() {
    local max_attempts=5
    local attempt=1
    local targets=()
    local timeout=5

    if [[ -n "$MODELS_CONFIG_URL" ]]; then
        targets+=("$MODELS_CONFIG_URL")
    fi
    targets+=("https://raw.githubusercontent.com")

    while (( attempt <= max_attempts )); do
        log_info "Checking internet connectivity (${attempt}/${max_attempts})..."
        for target in "${targets[@]}"; do
            if curl --head --silent --fail --max-time "$timeout" "$target" >/dev/null; then
                return 0
            fi
        done
        sleep 5
        ((attempt++))
    done

    return 1
}

install_uv() {
    if command -v uv >/dev/null 2>&1; then
        log_info "uv already installed."
        return
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "uv not found and no internet connection; skipping installation."
        return
    fi

    log_info "Installing uv package manager..."
    if curl -fsSL https://astral.sh/uv/install.sh | sh; then
        log_info "uv installation complete."
    else
        log_warn "uv installation failed; continuing without uv."
        return
    fi

    if ! command -v uv >/dev/null 2>&1; then
        log_warn "uv command not found after installation. Check PATH configuration."
    fi
}

download_config() {
    local url=$1
    local output=$2
    local max_attempts=5
    local attempt=1

    while (( attempt <= max_attempts )); do
        log_info "Downloading config from ${url} (${attempt}/${max_attempts})..."
        if curl -fsSL --connect-timeout 30 "$url" -o "$output"; then
            return 0
        fi
        log_warn "Config download failed on attempt ${attempt}. Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done

    return 1
}

ensure_models_config() {
    if [[ -f "$MODELS_CONFIG_PATH" ]]; then
        log_info "models_config.json already present; reusing existing file."
        return
    fi

    log_info "models_config.json missing; preparing configuration..."
    if [[ -n "$MODELS_CONFIG_URL" && "$HAS_INTERNET" -eq 1 ]]; then
        if download_config "$MODELS_CONFIG_URL" "$MODELS_CONFIG_PATH"; then
            log_info "Downloaded models_config.json from remote source."
            return
        fi
        log_warn "Failed to download models_config.json; falling back to default template."
    elif [[ -n "$MODELS_CONFIG_URL" ]]; then
        log_warn "MODELS_CONFIG_URL provided but no internet connection; using default template."
    fi

    cat <<'EOF' >"$MODELS_CONFIG_PATH"
{
    "checkpoints": [],
    "vae": [],
    "diffusion_models": [],
    "text_encoders": [],
    "loras": [],
    "upscale_models": [],
    "clip": [],
    "controlnet": [],
    "clip_vision": [],
    "ipadapter": [],
    "style_models": []
}
EOF
}

check_gpu() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log_warn "nvidia-smi not available; skipping GPU health check."
        return 1
    fi

    local timeout=30
    local interval=2
    local elapsed=0

    while (( elapsed < timeout )); do
        if nvidia-smi >/dev/null 2>&1; then
            log_info "GPU detected and ready."
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log_info "Waiting for GPU... (${elapsed}/${timeout} seconds)"
    done

    log_warn "GPU not detected after ${timeout} seconds."
    return 1
}

reset_gpu() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        return
    fi

    log_info "Resetting GPU state..."
    nvidia-smi --gpu-reset 2>/dev/null || true
    sleep 2
}

ensure_comfyui_repo() {
    if [[ -f "${COMFY_DIR}/main.py" ]]; then
        log_info "ComfyUI already present; skipping clone."
        return
    fi

    log_info "ComfyUI not found or incomplete; initializing fresh installation."
    if [[ -d "$COMFY_DIR" ]]; then
        log_warn "Removing existing ComfyUI directory before cloning."
        rm -rf "$COMFY_DIR"
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_error "Internet connection is required to clone ComfyUI. Aborting."
        exit 1
    fi

    log_info "Cloning ComfyUI repository..."
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI "$COMFY_DIR" 2>&1 | tee -a "$COMFY_LOG"
}

ensure_comfyui_structure() {
    mkdir -p "${COMFY_DIR}/models/"{checkpoints,vae,unet,diffusion_models,text_encoders,loras,upscale_models,clip,controlnet,clip_vision,ipadapter,style_models}
    mkdir -p "$CUSTOM_NODES_DIR" "${COMFY_DIR}/input" "${COMFY_DIR}/output" "${COMFY_DIR}/user/default/ComfyUI-Manager"
}

install_comfyui_dependencies() {
    if ! command -v uv >/dev/null 2>&1; then
        log_warn "uv not available; skipping ComfyUI dependency installation."
        return
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "No internet connection; skipping ComfyUI dependency installation."
        return
    fi

    if [[ ! -f "${COMFY_DIR}/requirements.txt" ]]; then
        log_warn "ComfyUI requirements.txt not found; skipping dependency installation."
        return
    fi

    pushd "$COMFY_DIR" >/dev/null
    # log_info "Installing PyTorch dependencies (CUDA 12.8 wheels)..."
    # uv pip install --no-cache torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128 2>&1 | tee -a "$COMFY_LOG"

    log_info "Installing PyTorch dependencies (CUDA 12.8 wheels)..."
    UV_PREFER_BINARY=1 PIP_NO_BUILD_ISOLATION=1 uv pip install --no-cache \
        torch torchvision torchaudio \
        --extra-index-url https://download.pytorch.org/whl/cu128 2>&1 | tee -a "$COMFY_LOG"


    # log_info "Installing ComfyUI Python requirements..."
    # uv pip install --no-cache -r requirements.txt 2>&1 | tee -a "$COMFY_LOG"

    UV_PREFER_BINARY=1 PIP_ONLY_BINARY="${PIP_ONLY_BINARY}" PIP_NO_BUILD_ISOLATION=1 \
      uv pip install --no-cache -r requirements.txt 2>&1 | tee -a "$COMFY_LOG"



    # log_info "Installing SageAttention 2.2.0 prebuilt wheel..."
    # uv pip install https://huggingface.co/Kijai/PrecompiledWheels/resolve/main/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl 2>&1 | tee -a "$COMFY_LOG"
    UV_PREFER_BINARY=1 PIP_NO_BUILD_ISOLATION=1 \
      uv pip install https://huggingface.co/Kijai/PrecompiledWheels/resolve/main/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl 2>&1 | tee -a "$COMFY_LOG"
    popd >/dev/null
}

ensure_comfyui_manager_config() {
    local config_path="${COMFY_DIR}/user/default/ComfyUI-Manager/config.ini"

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "Skipping ComfyUI Manager configuration download (offline mode)."
        return
    fi

    log_info "Updating ComfyUI Manager configuration..."
    if curl -fsSL "$COMFY_MANAGER_CONFIG_URL" -o "$config_path"; then
        log_info "ComfyUI Manager configuration updated."
    else
        log_warn "Failed to download ComfyUI Manager configuration."
    fi
}

install_custom_nodes_dependencies() {
    if ! command -v uv >/dev/null 2>&1; then
        log_warn "uv not available; skipping custom node dependency installation."
        return
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "No internet connection; skipping custom node dependency installation."
        return
    fi

    if [[ ! -d "$CUSTOM_NODES_DIR" ]]; then
        return
    fi

    log_info "Installing custom node requirements..."
    find "$CUSTOM_NODES_DIR" -name "requirements.txt" -print0 | while IFS= read -r -d '' req_file; do
        log_info "Installing dependencies from ${req_file}..."

        # uv pip install --no-cache -r "$req_file" 2>&1 | tee -a "$COMFY_LOG"
        UV_PREFER_BINARY=1 PIP_ONLY_BINARY="${PIP_ONLY_BINARY}" PIP_NO_BUILD_ISOLATION=1 \
          uv pip install --no-cache -r "$req_file" 2>&1 | tee -a "$COMFY_LOG"

    done
}

sync_custom_nodes() {
    ensure_comfyui_structure

    if [[ $SKIP_CUSTOM_NODES_DOWNLOAD == "true" ]]; then
        log_info "Skipping custom node dependency installation as per configuration."
        return
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "Skipping custom node clones (offline mode)."
        return
    fi

    mkdir -p "$CUSTOM_NODES_DIR"
    pushd "$CUSTOM_NODES_DIR" >/dev/null
    log_section "Download ComfyUI Nodes"

    for entry in "${CUSTOM_NODE_REPOS[@]}"; do
        local repo=${entry%%|*}
        local target_dir=${entry##*|}
        if [[ -d "$target_dir/.git" ]]; then
            log_info "Custom node ${target_dir} already present; skipping clone."
            continue
        fi

        log_info "Cloning ${target_dir}..."
        git clone --depth=1 "$repo" "$target_dir" 2>&1 | tee -a "$COMFY_LOG"
        du -sh "$target_dir" 2>/dev/null | tee -a "$COMFY_LOG" || true
    done

    if [[ -d "$CUSTOM_NODES_DIR" ]]; then
        log_info "Total size of custom nodes:"
        du -sh "$CUSTOM_NODES_DIR" 2>/dev/null | tee -a "$COMFY_LOG" || true
    fi

    popd >/dev/null

    install_custom_nodes_dependencies
    ensure_comfyui_manager_config
}

initialize_gpu() {
    log_info "Initializing GPU..."
    if check_gpu; then
        reset_gpu
    else
        log_warn "GPU initialization failed. Services may not function properly."
    fi
}

sync_models() {
    if [[ ! -f "$MODELS_CONFIG_PATH" ]]; then
        log_warn "models_config.json not found; skipping model synchronization."
        return
    fi

    log_info "Checking for missing models..."
    if python /utils/getInstalledModels.py --check-missing "$MODELS_CONFIG_PATH" | tee -a "$COMFY_LOG"; then
        log_info "All required models are present."
        return
    fi

    if [[ "$SKIP_MODEL_DOWNLOAD" == "true" ]]; then
        log_warn "Models missing but downloads are disabled via SKIP_MODEL_DOWNLOAD."
        return
    fi

    if [[ "$HAS_INTERNET" -eq 0 ]]; then
        log_warn "Models are missing and no internet connection is available to download them."
        return
    fi

    if [[ ! -f "$DOWNLOAD_MODELS_SCRIPT" ]]; then
        log_error "download_models.py not found at $DOWNLOAD_MODELS_SCRIPT; cannot download missing models."
        return
    fi

    log_info "Downloading missing models..."
    python "$DOWNLOAD_MODELS_SCRIPT" 2>&1 | tee -a "$LOG_PATH"
}

start_services() {
    log_info "Starting services..."

    CUDA_VISIBLE_DEVICES="" jupyter lab \
        --allow-root \
        --no-browser \
        --ip=0.0.0.0 \
        --port=8888 \
        --IdentityProvider.token="" \
        --ServerApp.allow_origin="'*'" \
        --ServerApp.password="" \
        --notebook-dir=/workspace &
    local jupyter_pid=$!
    log_info "Jupyter Lab started with PID: ${jupyter_pid}"

    sleep 5

    pushd "$COMFY_DIR" >/dev/null
    python -c "import torch; torch.cuda.empty_cache()" || true

    log_info "===================================================================="
    log_info "============ ComfyUI STARTING $(date) ============"
    log_info "===================================================================="
    log_info "Starting ComfyUI on port 8188..."

    if [[ "$USE_SAGE_ATTENTION" == "true" ]]; then
        python main.py --listen 0.0.0.0 --use-sage-attention --port 8188 2>&1 | tee -a "$COMFY_LOG" &
    else
        python main.py --listen 0.0.0.0 --port 8188 2>&1 | tee -a "$COMFY_LOG" &
    fi

    COMFY_PID=$!
    log_info "ComfyUI started with PID: ${COMFY_PID}"
    popd >/dev/null
}

main() {
    setup_workspace
    clean_log_file
    start_dashboard

    if check_internet; then
        HAS_INTERNET=1
        log_info "Internet connection is available."
    else
        log_warn "No internet connection detected after retries; continuing in offline mode."
    fi

    install_uv
    ensure_models_config
    ensure_comfyui_repo
    ensure_comfyui_structure
    sync_custom_nodes
    install_comfyui_dependencies
    initialize_gpu
    sync_models
    start_services

    wait
}

main "$@"
