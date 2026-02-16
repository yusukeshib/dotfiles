FROM debian:bookworm-slim

# Install dependencies needed for Nix and Claude Code
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git locales \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# Create user with passwordless sudo
RUN useradd -m -s /bin/sh -u 1000 yusuke \
    && echo 'yusuke ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/yusuke \
    && chmod 0440 /etc/sudoers.d/yusuke

# Install Nix (single-user mode, owned by yusuke)
RUN mkdir -m 0755 /nix && chown yusuke /nix
USER yusuke
ENV HOME=/home/yusuke
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
ENV PATH=$HOME/.local/bin:$HOME/.claude/bin:$HOME/.nix-profile/bin:$PATH
ENV PKG_CONFIG_PATH=$HOME/.nix-profile/lib/pkgconfig:$HOME/.nix-profile/share/pkgconfig

# Enable flakes and nix-command
RUN mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Shell & CLI tools
RUN nix profile install \
    nixpkgs#jq \
    nixpkgs#zsh \
    nixpkgs#bat \
    nixpkgs#delta \
    nixpkgs#eza \
    nixpkgs#fd \
    nixpkgs#fzf \
    nixpkgs#gh \
    nixpkgs#ripgrep \
    nixpkgs#openssh \
    nixpkgs#chezmoi

# Editors
RUN nix profile install \
    github:nix-community/neovim-nightly-overlay#neovim

# Languages & runtimes
RUN nix profile install \
    nixpkgs#nodejs \
    nixpkgs#uv \
    nixpkgs#cargo \
    nixpkgs#clippy \
    nixpkgs#rustfmt \
    nixpkgs#cargo-insta \
    nixpkgs#gcc

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
ENV SHELL=/home/yusuke/.nix-profile/bin/zsh
WORKDIR /home/yusuke
