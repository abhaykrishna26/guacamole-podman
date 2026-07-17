#!/bin/bash

sudo dnf update -y && sudo dnf upgrade -y
sudo dnf install -y nano unzip curl wget git

# ────────────────────────────────────────────────
#  Install podman
# ────────────────────────────────────────────────

sudo dnf install -y podman
podman --version
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
podman system migrate
podman info --log-level=debug
mkdir -p ~/.config/containers/systemd

# ────────────────────────────────────────────────
#  Install sysctl and enable port 80
# ────────────────────────────────────────────────

sudo dnf install procps-ng -y

# The sysctl is part of this package
# The procps-ng package provides a collection of essential command-line utilities for monitoring and managing processes, memory, and system performance.
# Changing net.ipv4.ip_unprivileged_port_start=80 allows the container to bind port 80 without needing special capabilities or running as root.

echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee -a /etc/sysctl.conf
sudo sysctl --system

# ────────────────────────────────────────────────
#  Ensure lingering is enabled for rootless systemd
# ────────────────────────────────────────────────

# By default, user’s systemd session ends when we log out, killing all processes including Podman containers.

if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
    echo "🔄 Enabling lingering for $USER..."
    sudo loginctl enable-linger "$USER" >/dev/null
fi

# ────────────────────────────────────────────────
#  install firewalld
# ────────────────────────────────────────────────

sudo dnf install firewalld -y
sudo systemctl start firewalld
sudo systemctl enable firewalld

# ────────────────────────────────────────────────
#  open port 8080 in firewall-cmd
# ────────────────────────────────────────────────

# Create firewall rule only if firewalld is installed and active
if command -v firewall-cmd &>/dev/null; then
    FIREWALL_STATUS=$(sudo firewall-cmd --state 2>/dev/null || echo "stopped")
    if [ "$FIREWALL_STATUS" = "running" ]; then
        echo "🧱 firewalld is running — applying firewall rules for port 8080"
        sudo firewall-cmd --permanent --zone=public --add-port=8080/tcp >/dev/null || echo "⚠️  Failed to add firewall rule"
        sudo firewall-cmd --reload >/dev/null || echo "⚠️  Failed to reload firewalld"
    else
        echo "ℹ️  firewalld installed but not running — skipping firewall configuration"
    fi
else
    echo "ℹ️  firewalld not installed — skipping firewall configuration"
fi
