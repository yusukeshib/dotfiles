FROM debian:bookworm-slim

# Install dependencies needed for Nix and Claude Code
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates sudo git \
    && rm -rf /var/lib/apt/lists/*

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

# Install chezmoi and nixy via nix (into yusuke's nix profile)
RUN nix profile install nixpkgs#chezmoi
RUN nix profile install github:yusukeshib/nixy

# Install zsh (git and curl are already provided by nixy)
RUN nix profile install nixpkgs#zsh
RUN nix profile install nixpkgs#gnused

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib --branch main && chezmoi apply

# Install all packages defined in nixy.json (targets /home/yusuke)
RUN nixy sync

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Initialize zplug and install plugins
RUN zsh -c 'source ~/.config/zsh/zplug.zsh'

# Set zsh as default shell and working directory
ENV SHELL=/home/yusuke/.nix-profile/bin/zsh
WORKDIR /home/yusuke
CMD ["zsh"]
