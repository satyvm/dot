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
    PATH=/home/ubuntu/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

RUN sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b /usr/local/bin

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

# The `t3` preset declares `ai: true` but is image-provisioned, so chezmoi
# never runs install-developer-tools.sh here. The agent toolchain has to be
# baked in instead, or `sync-nono-packs.sh` aborts `chezmoi apply` on first
# boot. Homebrew rather than npm wherever a formula exists: /home/linuxbrew is
# outside the t3-home volume, so these survive an image rebuild, whereas
# anything under /home/ubuntu is masked by the volume after the first deploy.
# All four have arm64_linux bottles, so this resolves without a source build.
RUN runuser -u ubuntu -- env HOME=/home/ubuntu NONINTERACTIVE=1 \
      HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1 \
      /home/linuxbrew/.linuxbrew/bin/brew install nono herdr opencode pi-coding-agent uv

# Crush lives in a third-party tap, so it is best effort: a tap outage should
# degrade one agent rather than fail the whole image build.
RUN runuser -u ubuntu -- env HOME=/home/ubuntu NONINTERACTIVE=1 \
      HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1 \
      /home/linuxbrew/.linuxbrew/bin/brew install charmbracelet/tap/crush \
    || echo "WARNING: crush was not installed; ax crush will be unavailable"

# Claude Code and Codex have no Linux formula — npm is their only provider.
# T3 Code itself stays here too so `npm i -g t3@latest` upgrades it in place
# without an image rebuild. The entrypoint reconciles this directory on boot,
# because the t3-home volume masks image updates to it.
RUN runuser -u ubuntu -- env HOME=/home/ubuntu npm install -g \
      t3@latest \
      @anthropic-ai/claude-code@latest \
      @openai/codex@latest \
    && runuser -u ubuntu -- env HOME=/home/ubuntu /home/ubuntu/.npm-global/bin/t3 --version

# Fail the build rather than ship an image whose ax cannot run.
RUN for tool in nono herdr opencode pi claude codex t3; do \
      runuser -u ubuntu -- env HOME=/home/ubuntu PATH="$PATH" \
        command -v "$tool" >/dev/null \
        || { echo "missing required tool: $tool"; exit 1; }; \
    done

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
      > /etc/ssh/sshd_config.d/99-t3code.conf

COPY supervisord.conf /etc/supervisor/conf.d/t3code.conf
COPY entrypoint.sh /usr/local/bin/t3code-entrypoint
COPY gitea_ai_cli.py /usr/local/bin/gitea-ai
RUN chmod 0555 /usr/local/bin/t3code-entrypoint /usr/local/bin/gitea-ai

EXPOSE 22 3773
ENTRYPOINT ["/usr/local/bin/t3code-entrypoint"]
