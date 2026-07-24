#!/usr/bin/env bash
set -euo pipefail

# Ensure SSH host keys persist in /etc/ssh/host-keys
mkdir -p /etc/ssh/host-keys
if [[ ! -f /etc/ssh/host-keys/ssh_host_ed25519_key ]]; then
  ssh-keygen -t ed25519 -f /etc/ssh/host-keys/ssh_host_ed25519_key -N ""
fi
if [[ ! -f /etc/ssh/host-keys/ssh_host_rsa_key ]]; then
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/host-keys/ssh_host_rsa_key -N ""
fi

ln -sfn /etc/ssh/host-keys/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
ln -sfn /etc/ssh/host-keys/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
ln -sfn /etc/ssh/host-keys/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
ln -sfn /etc/ssh/host-keys/ssh_host_rsa_key.pub /etc/ssh/ssh_host_rsa_key.pub

chmod 600 /etc/ssh/host-keys/*_key
chmod 644 /etc/ssh/host-keys/*.pub

# Setup user ubuntu SSH authorized_keys
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
if [[ -n "${DEV_SSH_PUBLIC_KEY:-}" ]]; then
  echo "$DEV_SSH_PUBLIC_KEY" > /home/ubuntu/.ssh/authorized_keys
  chmod 600 /home/ubuntu/.ssh/authorized_keys
fi
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Ensure development workspace path exists
mkdir -p /home/ubuntu/dev
chown -R ubuntu:ubuntu /home/ubuntu/dev /home/ubuntu

# Run supervisord
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
