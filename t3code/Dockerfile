# T3 Code remote development environment.
#
# Deliberately minimal compared to the image it replaces: no web UI, no Python
# agent runtime, no supervisor-managed application server beyond sshd and the
# T3 Code node server. Everything else is installed by chezmoi at first boot
# from the repository's own `t3` machine preset.
FROM node:22.19.0-bookworm

ARG REMOTE_UID=1000
ARG REMOTE_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    T3CODE_HOME=/home/ubuntu/.t3 \
    NPM_CONFIG_PREFIX=/home/ubuntu/.npm-global \
    PATH=/home/ubuntu/.local/bin:/home/ubuntu/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Build toolchain is required: T3 Code compiles native dependencies on install.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      age \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      file \
      g++ \
      git \
      git-lfs \
      gnupg \
      gzip \
      jq \
      locales \
      make \
      openssh-server \
      pkg-config \
      procps \
      python3 \
      python3-dev \
      python3-venv \
      sudo \
      supervisor \
      tar \
      unzip \
      util-linux \
      zsh \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
    && locale-gen

# The SSH and editor identity matches the Ubuntu host account that owns the
# bind-mounted workspace.
RUN if getent group "${REMOTE_GID}" >/dev/null; then \
      groupmod -n ubuntu "$(getent group "${REMOTE_GID}" | cut -d: -f1)"; \
    else \
      groupadd --gid "${REMOTE_GID}" ubuntu; \
    fi \
    && if getent passwd "${REMOTE_UID}" >/dev/null; then \
         userdel -r "$(getent passwd "${REMOTE_UID}" | cut -d: -f1)" 2>/dev/null || true; \
       fi \
    && useradd --uid "${REMOTE_UID}" --gid "${REMOTE_GID}" \
      --home-dir /home/ubuntu --create-home --shell /bin/zsh ubuntu \
    && passwd --delete ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && install -d -o ubuntu -g ubuntu \
      /home/ubuntu/dev \
      /home/ubuntu/.t3 \
      /home/ubuntu/.npm-global \
      /home/ubuntu/.config \
      /home/ubuntu/.local/bin \
      /home/ubuntu/.local/share \
      /home/ubuntu/.local/state

# Homebrew on Linux ARM64 became a Tier 1 target in Homebrew 5.0.0, so the
# repository's Brewfile works unchanged on the Ampere host.
RUN install -d -o ubuntu -g ubuntu /home/linuxbrew /home/linuxbrew/.linuxbrew \
    && runuser -u ubuntu -- git clone --depth=1 \
      https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew \
    && install -d -o ubuntu -g ubuntu /home/linuxbrew/.linuxbrew/bin \
    && runuser -u ubuntu -- ln -s ../Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew \
    && runuser -u ubuntu -- env HOME=/home/ubuntu NONINTERACTIVE=1 \
      HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1 \
      /home/linuxbrew/.linuxbrew/bin/brew --version

# chezmoi is the bootstrap tool, so it is the one thing that cannot come from
# the catalog it installs. Everything else — the cli, developer and ai tiers —
# is installed by `chezmoi apply` at first boot from .chezmoidata/packages.yaml
# into the persistent /home/linuxbrew volume, exactly as on every other machine.
# Nothing is duplicated between this file and the catalog.
RUN sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b /usr/local/bin

# T3 Code is the server this image exists to run and is not in the catalog, so
# it stays here. The entrypoint reconciles it on boot because the t3-home
# volume masks image updates under /home/ubuntu.
RUN runuser -u ubuntu -- env HOME=/home/ubuntu npm install -g t3@latest \
    && runuser -u ubuntu -- env HOME=/home/ubuntu /home/ubuntu/.npm-global/bin/t3 --version

# Fail the build rather than ship an image that cannot bootstrap itself. Only
# the bootstrap set is checked; the catalog's tools arrive at first boot.
RUN missing=""; \
    for tool in brew chezmoi node npm t3; do \
      if resolved=$(runuser -u ubuntu -- env HOME=/home/ubuntu PATH="$PATH" \
                      sh -c "command -v $tool" 2>/dev/null); then \
        echo "  ok  $tool -> $resolved"; \
      else \
        echo "  MISSING  $tool"; missing="$missing $tool"; \
      fi; \
    done; \
    if [ -n "$missing" ]; then echo "required tools missing:$missing"; exit 1; fi

RUN install -d /var/run/sshd /etc/ssh/host-keys \
    && printf '%s\n' \
      'HostKey /etc/ssh/host-keys/ssh_host_ed25519_key' \
      'PermitRootLogin no' \
      'PasswordAuthentication no' \
      'PermitEmptyPasswords no' \
      'KbdInteractiveAuthentication no' \
      'PubkeyAuthentication yes' \
      'AllowUsers ubuntu' \
      'AllowAgentForwarding no' \
      'AllowTcpForwarding yes' \
      'X11Forwarding no' \
      'UsePAM no' \
      'SetEnv PATH=/home/ubuntu/.local/bin:/home/ubuntu/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
      > /etc/ssh/sshd_config.d/99-t3code.conf

COPY supervisord.conf /etc/supervisor/conf.d/t3code.conf
COPY entrypoint.sh /usr/local/bin/t3code-entrypoint
COPY gitea_ai_cli.py /usr/local/bin/gitea-ai
RUN chmod 0555 /usr/local/bin/t3code-entrypoint /usr/local/bin/gitea-ai

EXPOSE 22 3773
ENTRYPOINT ["/usr/local/bin/t3code-entrypoint"]
