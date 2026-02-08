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
