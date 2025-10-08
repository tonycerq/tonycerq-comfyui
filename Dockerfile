FROM tailscale/tailscale:latest AS tailscale
FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS builder

ARG PYTHON_VERSION="3.12"
ARG CONTAINER_TIMEZONE=UTC 

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="${PATH}:/root/.local/bin:/root/.cargo/bin"

# --- 1. INSTALLATION AND CONFIGURATION ---


# Install system dependencies including CUDA development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    git \
    build-essential \
    libgl1-mesa-dev \
    libglib2.0-0 \
    wget \
    ffmpeg \
    aria2 \
    rsync \
    curl \
    ca-certificates \
    fzf \
    ripgrep \
    fd-find \
    bat \
    nvtop \
    btop \
    jq \
    httpie \
    curl \
    wget \
    tree \
    gnupg \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    neovim \
    zoxide \
    nmap \
    eza \
    lsof \
    && rm -rf /var/lib/apt/lists/*

RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update --yes && \
    apt-get install --yes --no-install-recommends python3-pip "python${PYTHON_VERSION}" "python${PYTHON_VERSION}-venv" && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Copy tailscale binaries
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/tailscale  /usr/local/bin/tailscale

# Install uv package installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate virtual environment
RUN python${PYTHON_VERSION} -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Set working directory to root
WORKDIR /

# Install Jupyter and FastAPI dependencies with uv
RUN uv pip install --no-cache \
    jupyter \
    jupyterlab \
    nodejs \
    requests \
    fastapi \
    uvicorn \
    websockets \
    pydantic \
    jinja2 \
    gdown \
    onnxruntime-gpu \
    pip \
    "numpy<2"

RUN uv pip install --no-cache triton

# Setup Jupyter configuration
RUN jupyter notebook --generate-config && \
    echo "c.ServerApp.allow_root = True" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.ServerApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.IdentityProvider.token = ''" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.ServerApp.password = ''" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.ServerApp.allow_origin = '*'" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.ServerApp.allow_remote_access = True" >> /root/.jupyter/jupyter_notebook_config.py

# clear cache to free up space 
RUN uv cache clean 
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Create workspace directory
RUN mkdir -p /workspace
RUN mkdir -p /notebooks /notebooks/dto /notebooks/utils /notebooks/workers /notebooks/web/static /notebooks/web/templates

# Copy scripts to root
WORKDIR /notebooks
COPY start.sh .
COPY download_models.py .
COPY ./constants/ ./constants/
COPY ./dto/ ./dto/
COPY ./workers/ ./workers/
COPY ./utils/ ./utils/
COPY ./web/ ./web/

RUN ls -la

COPY models_config.json /workspace

# JupyterLab theme settings
RUN mkdir -p /root/.jupyter/lab/user-settings/@jupyterlab/apputils-extension
COPY themes.jupyterlab-settings /root/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/


# Make scripts executable
RUN chmod +x *.sh

# --- 2. ADD CUSTOM SHELL ALIASES AND GIT CONFIGURATIONS ---

RUN cat <<EOF > /root/.bash_aliases
# Custom Shell Aliases
alias btop='/usr/bin/btop --utf-force'
alias n='/usr/bin/nvim'
alias fd='fdfind'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias d='docker'
alias decompress='tar -xzf'
alias ff='fzf --preview "bat --style=numbers --color=always {}"'
alias g='git'
alias gcad='git commit -a --amend'
alias gcam='git commit -a -m'
alias gcm='git commit -m'
alias gfixup='git add -A; git commit --no-verify --fixup=HEAD'
alias gs='git status'
alias gst='git status'
alias gunwip='git rev-list --max-count=1 --format="%s" HEAD | grep -q "🚧 wip:" && git reset HEAD~1'
alias gwip='git add -A; git rm \$(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "🚧 wip: work in progress [skip ci]"'
alias ls='eza -lh --group-directories-first --icons=auto'
alias l='ls -lha'
alias lsa='ls -a'
alias lt='eza --tree --level=2 --long --icons --git'
alias lta='lt -a'
alias rc='n ~/.bashrc'
alias rca='n ~/.config/bash/aliases'
alias rce='n ~/.config/bash/envs'
EOF

# --- 3. FINALIZATION ---

# Expose ports
EXPOSE 8188 8888 8189 22

CMD ["./start.sh"]
