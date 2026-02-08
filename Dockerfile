FROM nixos/nix

# Enable flakes and nix-command
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Create user and grant nix store access (single-user mode)
RUN echo "yusuke:x:1000:1000:yusuke:/home/yusuke:/bin/sh" >> /etc/passwd && \
    echo "yusuke:x:1000:" >> /etc/group && \
    mkdir -p /home/yusuke && \
    chown -R yusuke /home/yusuke /nix

# Switch to yusuke — all subsequent commands run as yusuke in /home/yusuke
USER yusuke
ENV HOME=/home/yusuke
ENV PATH=/home/yusuke/.nix-profile/bin:$PATH

# Install chezmoi and nixy via nix (into yusuke's nix profile)
RUN nix profile install nixpkgs#chezmoi
RUN nix profile install github:yusukeshib/nixy

# Install zsh (git and curl are already provided by nixy)
RUN nix profile install nixpkgs#zsh

# Init and apply dotfiles (targets /home/yusuke)
RUN chezmoi init yusukeshib && chezmoi apply

# Install all packages defined in nixy.json (targets /home/yusuke)
RUN nixy sync

# Install Claude Code via npm (native binary won't run on NixOS)
RUN nix profile install nixpkgs#nodejs && npm install -g @anthropic-ai/claude-code

# Initialize zplug and install plugins
COPY .config/zsh/zplug.zsh /tmp/zplug.zsh
RUN zsh -c 'source /tmp/zplug.zsh'

# Set zsh as default shell and working directory
ENV SHELL=/home/yusuke/.nix-profile/bin/zsh
WORKDIR /home/yusuke
CMD ["zsh"]
