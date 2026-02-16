FROM debian:bookworm-slim

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git locales \
    jq zsh bat fd-find fzf ripgrep openssh-client gcc \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# Create user with passwordless sudo
RUN useradd -m -s /usr/bin/zsh -u 1000 yusuke \
    && echo 'yusuke ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/yusuke \
    && chmod 0440 /etc/sudoers.d/yusuke

USER yusuke
ENV HOME=/home/yusuke
ENV PATH=$HOME/.local/bin:$HOME/.claude/bin:$HOME/.cargo/bin:$PATH

# Install CLI tools from GitHub releases
ARG GH_VERSION=2.67.0
ARG DELTA_VERSION=0.18.2
ARG EZA_VERSION=0.20.14
RUN mkdir -p ~/.local/bin \
    # gh
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
       | tar xz -C /tmp \
    && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh ~/.local/bin/ \
    && rm -rf /tmp/gh_* \
    # delta (musl static binary)
    && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
       | tar xz -C /tmp \
    && mv /tmp/delta-${DELTA_VERSION}-x86_64-unknown-linux-musl/delta ~/.local/bin/ \
    && rm -rf /tmp/delta-* \
    # eza (musl static binary, single file in tarball)
    && curl -fsSL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_x86_64-unknown-linux-musl.tar.gz" \
       | tar xz -C ~/.local/bin

# Install chezmoi
RUN sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b ~/.local/bin

# Install Neovim nightly
RUN curl -fsSL "https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz" \
    | tar xz --strip-components=1 -C ~/.local

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Rust via rustup (includes cargo, clippy, rustfmt)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default \
    && . "$HOME/.cargo/env" \
    && cargo install cargo-insta

# Install Node.js
ARG NODE_VERSION=22.13.1
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar xJ --strip-components=1 -C ~/.local

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib && chezmoi apply

# Trust all directories for git safe.directory (needed for mounted workspaces in container)
RUN git config --global --add safe.directory '*'

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI (standalone binary, no Node.js needed)
RUN mkdir -p ~/.local/bin \
    && curl -fsSL https://github.com/openai/codex/releases/latest/download/codex-x86_64-unknown-linux-musl.tar.gz \
    | tar xz -C /tmp \
    && mv /tmp/codex-x86_64-unknown-linux-musl ~/.local/bin/codex \
    && chmod +x ~/.local/bin/codex

# Set zsh as default shell and working directory
ENV SHELL=/usr/bin/zsh
WORKDIR /home/yusuke
