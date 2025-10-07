FROM promptalchemist/comfyui-docker-new:latest

# --- 1. INSTALL DEVELOPMENT TOOLS AND SSH ---
# We install openssh-server here to ensure it is present in the final layer, 
# even though the base entrypoint will handle starting the service.
RUN apt update && \
    apt install -y --no-install-recommends \
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
    gnupg \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    neovim \
    aria2 \
    zoxide \
    nmap \
    eza; \
    rm -rf /var/lib/apt/lists/*

# --- 2. ADD CUSTOM SHELL ALIASES AND GIT CONFIGURATIONS ---

# 2a. Create the aliases script using a reliable, standalone RUN command for the heredoc.
# Aliases are written to a script in /etc/profile.d/, which is sourced 
# by interactive non-login shells (like when using 'docker exec -it bash').
RUN cat <<EOF > /etc/profile.d/99-custom-aliases.sh
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

# 2b. Set permissions and apply Git configurations in a separate RUN command.
RUN chmod +x /etc/profile.d/99-custom-aliases.sh && \
    # Apply global Git configurations
    git config --global alias.a 'add' && \
    git config --global alias.ps 'push' && \
    git config --global alias.pl 'pull' && \
    git config --global alias.l 'log' && \
    git config --global alias.c 'commit -m' && \
    git config --global alias.s 'status' && \
    git config --global alias.co 'checkout' && \
    git config --global alias.b 'branch'

RUN echo 'eval "$(zoxide init bash)"' >> ~/.bashrc