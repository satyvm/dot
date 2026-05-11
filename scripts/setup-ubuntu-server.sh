#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit
fi

echo "Updating and upgrading system..."
apt update && apt upgrade -y

echo "Setting timezone to IST..."
timedatectl set-timezone Asia/Kolkata
timedatectl set-ntp true
timedatectl

read -p "Do you want to create a new user? (y/n): " create_user
if [[ $create_user =~ ^[Yy]$ ]]; then
    read -p "Enter new username: " username
    adduser $username
    usermod -aG sudo $username
    echo "Disabling root SSH login..."
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
fi

echo "Configuring UFW firewall..."
apt install ufw -y
ufw allow OpenSSH
ufw enable

echo "Installing essential tools..."
apt install -y curl wget git vim htop iotop iftop tmux

echo "Configuring advanced security..."
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy