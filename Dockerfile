FROM debian:bookworm-slim

# Install dependencies needed for Nix and Claude Code
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git locales \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Create user
RUN useradd -m -s /bin/sh -u 1000 yusuke

# Install Nix (single-user mode, owned by yusuke)
RUN mkdir -m 0755 /nix && chown yusuke /nix
USER yusuke
ENV HOME=/home/yusuke
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
ENV PATH=/home/yusuke/.nix-profile/bin:$PATH

# Enable flakes and nix-command
RUN mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# base
RUN nix profile install nixpkgs#zsh
RUN nix profile install nixpkgs#awscli
RUN nix profile install nixpkgs#bat
RUN nix profile install nixpkgs#delta
RUN nix profile install nixpkgs#direnv
RUN nix profile install nixpkgs#entr
RUN nix profile install nixpkgs#eza
RUN nix profile install nixpkgs#fd
RUN nix profile install nixpkgs#fzf
RUN nix profile install nixpkgs#gh
RUN nix profile install nixpkgs#ripgrep
RUN nix profile install nixpkgs#starship

# work
RUN nix profile install nixpkgs#uv
RUN nix profile install nixpkgs#kubectx
RUN nix profile install nixpkgs#kubernetes-helm
# graphite-cli
# terraform

# rust
RUN nix profile install nixpkgs#cargo
RUN nix profile install nixpkgs#clippy
RUN nix profile install nixpkgs#rustfmt

# Install chezmoi
RUN nix profile install nixpkgs#chezmoi

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib --branch main && chezmoi apply

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH=/home/yusuke/.local/bin:/home/yusuke/.claude/bin:$PATH

# Set zsh as default shell and working directory
ENV SHELL=/home/yusuke/.nix-profile/bin/zsh
WORKDIR /home/yusuke
CMD ["zsh"]
