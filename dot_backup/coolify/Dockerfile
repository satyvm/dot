ARG HERMES_WEBUI_VERSION=0.51.92
FROM node:22.17.0-bookworm-slim AS node-runtime

FROM ghcr.io/nesquena/hermes-webui:${HERMES_WEBUI_VERSION}

ARG REMOTE_UID=1000
ARG REMOTE_GID=1000
ARG HERMES_AGENT_VERSION=0.18.2
ARG CLAUDE_CODE_VERSION=2.1.15
ARG OPENCODE_VERSION=1.18.0
ARG PI_VERSION=0.81.1

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    HERMES_HOME=/home/ubuntu/.hermes \
    HERMES_WEBUI_STATE_DIR=/home/ubuntu/.hermes/webui \
    HERMES_WEBUI_DEFAULT_WORKSPACE=/home/ubuntu/dev \
    HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_PYTHON=/opt/hermes-venv/bin/python \
    PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/opt/hermes-venv/bin:/usr/local/bin:/usr/bin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      fd-find \
      git \
      gzip \
      jq \
      openssh-server \
      procps \
      python3-venv \
      ripgrep \
      shellcheck \
      supervisor \
      tar \
      tmux \
      unzip \
      util-linux \
      zsh \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node-runtime /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version \
    && npm --version

# The SSH/editor identity intentionally matches the Ubuntu host account. The
# existing upstream hermeswebui user remains unused by this derived image.
RUN if getent group "${REMOTE_GID}" >/dev/null; then \
      existing_group="$(getent group "${REMOTE_GID}" | cut -d: -f1)"; \
      groupmod -n ubuntu "${existing_group}"; \
    else \
      groupadd --gid "${REMOTE_GID}" ubuntu; \
    fi \
    && useradd --uid "${REMOTE_UID}" --gid "${REMOTE_GID}" \
      --home-dir /home/ubuntu --create-home --shell /bin/zsh ubuntu \
    && install -d -o ubuntu -g ubuntu \
      /home/ubuntu/dev \
      /home/ubuntu/.config \
      /home/ubuntu/.local/bin \
      /home/ubuntu/.local/share \
      /home/ubuntu/.local/state \
    && chown -R ubuntu:ubuntu /apptoo

# Install the versioned Hermes runtime into an isolated interpreter. WebUI's
# server.py is deliberately launched with this interpreter.
RUN python3 -m venv /opt/hermes-venv \
    && /opt/hermes-venv/bin/pip install --no-cache-dir \
      "hermes-agent==${HERMES_AGENT_VERSION}"

# Install chezmoi and age without architecture-specific archives.
RUN sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b /usr/local/bin \
    && apt-get update \
    && apt-get install -y --no-install-recommends age \
    && rm -rf /var/lib/apt/lists/*

# Install Linuxbrew for the pinned agent formulas already managed by this
# repository. The repository's Brewfile remains the user-facing source of truth.
RUN install -d -o ubuntu -g ubuntu /home/linuxbrew/.linuxbrew/Homebrew \
    /home/linuxbrew/.linuxbrew/bin \
    && runuser -u ubuntu -- git clone --depth=1 \
      https://github.com/Homebrew/brew \
      /home/linuxbrew/.linuxbrew/Homebrew \
    && ln -s ../Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew \
    && runuser -u ubuntu -- env \
      HOME=/home/ubuntu \
      HOMEBREW_NO_ANALYTICS=1 \
      HOMEBREW_NO_AUTO_UPDATE=1 \
      /home/linuxbrew/.linuxbrew/bin/brew install \
        bat \
        eza \
        fd \
        fzf \
        gh \
        git-delta \
        gopls \
        herdr \
        lazygit \
        neovim \
        nono \
        rust-analyzer \
        starship \
        uv \
        zoxide \
        charmbracelet/tap/crush

# Node-distributed agents and language servers are pinned explicitly.
RUN npm install --global \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
      "@earendil-works/pi-coding-agent@${PI_VERSION}" \
      "@vtsls/language-server@0.3.0" \
      "pyright@1.1.411" \
      "@modelcontextprotocol/server-filesystem@0.6.2" \
      "@modelcontextprotocol/server-github@0.6.2"

RUN install -d /var/run/sshd /etc/ssh/host-keys \
    && printf '%s\n' \
      'HostKey /etc/ssh/host-keys/ssh_host_ed25519_key' \
      'HostKey /etc/ssh/host-keys/ssh_host_rsa_key' \
      'PermitRootLogin no' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PubkeyAuthentication yes' \
      'AllowUsers ubuntu' \
      'AllowAgentForwarding no' \
      'AllowTcpForwarding yes' \
      'X11Forwarding no' \
      'UsePAM no' \
      > /etc/ssh/sshd_config.d/99-hermes-dev.conf

COPY supervisord.conf /etc/supervisor/conf.d/hermes-dev.conf
COPY entrypoint.sh /usr/local/bin/hermes-dev-entrypoint
RUN chmod 0555 /usr/local/bin/hermes-dev-entrypoint

EXPOSE 22 8787

HEALTHCHECK --interval=30s --timeout=8s --start-period=30s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:8787/health >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/hermes-dev-entrypoint"]
