FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    supervisor \
    curl \
    wget \
    git \
    zsh \
    tar \
    gzip \
    ca-certificates \
    jq \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    golang \
    ripgrep \
    eza \
    bat \
    zoxide \
    sudo \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH server
RUN mkdir -p /var/run/sshd /etc/ssh/host-keys \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config

# Configure ubuntu user (default UID/GID 1000 in Ubuntu 24.04)
RUN id ubuntu || useradd -m -s /bin/zsh -u 1000 ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

# Install chezmoi & age
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin \
    && curl -fsSL -o /tmp/age.tar.gz https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz \
    && tar -xzf /tmp/age.tar.gz -C /tmp \
    && mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/ \
    && rm -rf /tmp/age*

# Install Hermes Agent and clone & build Hermes WebUI
RUN pip install --no-cache-dir hermes-agent \
    && git clone https://github.com/nesquena/hermes-webui.git /opt/hermes-webui \
    && cd /opt/hermes-webui \
    && npm ci || npm install \
    && npm run build || true \
    && mkdir -p /home/ubuntu/dev \
    && chown -R ubuntu:ubuntu /opt/hermes-webui /home/ubuntu/dev

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1:8787/health || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
