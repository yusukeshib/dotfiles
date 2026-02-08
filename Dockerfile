FROM nixos/nix

# Enable flakes and nix-command
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Install chezmoi and nixy via nix
RUN nix profile install nixpkgs#chezmoi
RUN nix profile install github:yusukeshib/nixy

# Install zsh (git and curl are already provided by nixy)
RUN nix profile install nixpkgs#zsh

# Init and apply dotfiles
RUN chezmoi init yusukeshib && chezmoi apply

# Install all packages defined in nixy.json
RUN nixy sync

# Install Claude Code via npm (native binary won't run on NixOS)
RUN nix profile install nixpkgs#nodejs && npm install -g @anthropic-ai/claude-code

# Set zsh as default shell and working directory
ENV SHELL=/root/.nix-profile/bin/zsh
WORKDIR /root
CMD ["zsh"]
