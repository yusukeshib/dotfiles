# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git locales \
    jq zsh bat fd-find ripgrep openssh-client \
    libvulkan1 mesa-vulkan-drivers \
    libc6-dev build-essential pkg-config cmake nasm libfontconfig1-dev libssl-dev libvulkan-dev \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# Create user with passwordless sudo
RUN useradd -m -s /usr/bin/zsh -u 501 yusuke \
    && echo 'yusuke ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/yusuke \
    && chmod 0440 /etc/sudoers.d/yusuke

# Resolve arch-specific identifiers once and stash them in /etc/arch-env
# so all subsequent RUN layers can `. /etc/arch-env` instead of re-casing.
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) GO_A=amd64; RUST_A=x86_64; NODE_A=x64;   DELTA_V=musl ;; \
      arm64) GO_A=arm64; RUST_A=aarch64; NODE_A=arm64; DELTA_V=gnu  ;; \
      *) echo "unsupported arch: $TARGETARCH"; exit 1 ;; \
    esac; \
    printf 'export GO_A=%s\nexport RUST_A=%s\nexport NODE_A=%s\nexport DELTA_V=%s\n' \
      "$GO_A" "$RUST_A" "$NODE_A" "$DELTA_V" > /etc/arch-env

USER yusuke
ENV HOME=/home/yusuke
ENV PATH=$HOME/.local/bin:$HOME/.claude/bin:$HOME/.cargo/bin:$PATH

# Install CLI tools from GitHub releases
ARG FZF_VERSION=0.61.1
ARG GH_VERSION=2.67.0
ARG DELTA_VERSION=0.18.2
ARG EZA_VERSION=0.20.14
RUN set -eux; . /etc/arch-env; \
    mkdir -p ~/.local/bin; \
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${GO_A}.tar.gz" \
      | tar xz -C ~/.local/bin; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GO_A}.tar.gz" \
      | tar xz -C /tmp; \
    mv /tmp/gh_${GH_VERSION}_linux_${GO_A}/bin/gh ~/.local/bin/; \
    rm -rf /tmp/gh_*; \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${RUST_A}-unknown-linux-${DELTA_V}.tar.gz" \
      | tar xz -C /tmp; \
    mv /tmp/delta-${DELTA_VERSION}-${RUST_A}-unknown-linux-${DELTA_V}/delta ~/.local/bin/; \
    rm -rf /tmp/delta-*; \
    curl -fsSL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${RUST_A}-unknown-linux-musl.tar.gz" \
      | tar xz -C ~/.local/bin

# Install chezmoi
RUN sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b ~/.local/bin

# Install Neovim nightly
RUN set -eux; . /etc/arch-env; \
    case "$RUST_A" in \
      x86_64)  NVIM_A=x86_64 ;; \
      aarch64) NVIM_A=arm64  ;; \
    esac; \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-${NVIM_A}.tar.gz" \
      | tar xz --strip-components=1 -C ~/.local

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Rust via rustup (includes cargo, clippy, rustfmt) + cargo-insta.
# Use buildkit cache mounts so the cargo registry/build artifacts are reused across builds.
RUN --mount=type=cache,target=/home/yusuke/.cargo/registry,uid=501 \
    --mount=type=cache,target=/home/yusuke/.cargo/git,uid=501 \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default \
    && . "$HOME/.cargo/env" \
    && cargo install cargo-insta

# Install Node.js
ARG NODE_VERSION=22.13.1
RUN set -eux; . /etc/arch-env; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_A}.tar.xz" \
      | tar xJ --strip-components=1 -C ~/.local

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib && chezmoi apply

# Trust all directories for git safe.directory (needed for mounted workspaces in container)
RUN git config --global --add safe.directory '*'

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI (standalone binary, no Node.js needed)
RUN set -eux; . /etc/arch-env; \
    mkdir -p ~/.local/bin; \
    curl -fsSL "https://github.com/openai/codex/releases/latest/download/codex-${RUST_A}-unknown-linux-musl.tar.gz" \
      | tar xz -C /tmp; \
    mv /tmp/codex-${RUST_A}-unknown-linux-musl ~/.local/bin/codex; \
    chmod +x ~/.local/bin/codex

# Set zsh as default shell and working directory
ENV SHELL=/usr/bin/zsh
WORKDIR /home/yusuke
