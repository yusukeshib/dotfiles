FROM debian:bookworm-slim

# Install dependencies needed for Nix and Claude Code
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git locales \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

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
    nixpkgs#rustfmt

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib && chezmoi apply

# Trust all directories for git safe.directory (needed for mounted workspaces in container)
RUN git config --global --add safe.directory '*'

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Set zsh as default shell and working directory
ENV SHELL=/home/yusuke/.nix-profile/bin/zsh
WORKDIR /home/yusuke
