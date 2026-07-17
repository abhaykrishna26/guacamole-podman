## 🚀 Guacamole Stack Deployment Guide

A fully automated script for deploying **Apache Guacamole**, **MySQL**, and **guacd** using **Podman Quadlet** and **systemd user services**.  
Supports **OIDC authentication**, secure **Podman secrets**, and a **persistent state file** that remembers configuration across runs.

---

# 📚 Table of Contents
- [Folder Structure](#folder-structure)
- [Features](#features)
- [Quick Start](#quick-start)
- [Full Instructions](#full-instructions)
- [File Structure](#file-structure)
- [CLI Options](#cli-options)
- [State File Details](#state-file-details)
- [Reset State](#reset-state)
- [Secret Management](#secret-management)
- [Backup & Restore](#backup--restore)
- [Systemd Commands](#systemd-commands)
- [Upgrade Instructions](#upgrade-instructions)
- [Uninstall](#uninstall)
- [➡ OIDC SSO Setup Guide](guacamole/README-OIDC-SETUP.md)

---

## 📁 Folder Structure

```
LAB/
└── guacamole/
    ├── deploy-guacamole-stack.sh
    ├── install-podman.sh
    ├── README-OIDC-SETUP.md
    └── README.md
```

## ⭐ Features

### ✔ Automated container deployment
- MySQL (persistent)
- guacd proxy
- Guacamole web UI
- Managed via systemd user services
- Auto-generated Podman Quadlet (`*.container`) files  
- Opens port **8080**

### ✔ Secure Podman secrets
- MySQL root password  
- MySQL user password  
- OIDC client secret  
- Supports rotation and reuse

### ✔ Persistent state file
```
~/.config/containers/systemd/guacamole/guacamole.state
```

Priority:
1. CLI arguments  
2. Saved state  
3. Defaults  

### ✔ Optional OIDC Login (Azure AD / Entra)

---

# 💻 Quick Start

## 1. Make scripts executable
```bash
chmod +x install-podman.sh deploy-guacamole-stack.sh
```

## 2. Install Podman + Open Port 8080 in firewalld
```bash
sudo bash install-podman.sh
```

## 3. First deployment run
```bash
bash deploy-guacamole-stack.sh

# Check status
podman ps
# OR
podman logs guacamole
```

### Login defaults:

URL:  `http://localhost:8080/`

Username / Password: `guacadmin / guacadmin`

Now we have a working guacamole, Configure https using nginx-proxy-manager.

## 4. Enable OIDC   -   ([OIDC SSO Setup Guide](guacamole/OIDC-SSO-Setup-Guide.md))
```bash
bash deploy-guacamole-stack.sh --enable-oidc \
  --oidc-tenant-id=<entra-tenant-id> \
  --oidc-client-id=<entra-app-client-id> \
  --oidc-redirect-uri=<https://<guacamole-public-url>/
```

## 5. Set OIDC login as default (only after giving Admin permissions to your Office365 account)
```bash
bash deploy-guacamole-stack.sh --extension-priority="openid, mysql, ban"
```

---

## 🗂 File Structure

| File | Purpose |
|------|---------|
| `*.container` | Quadlet files |
| `mysql-data/` | MySQL persistent storage |
| `guacamole.state` | Saved last-used config |
| Podman secrets | Stored securely |

---

# ⚙️ CLI Options

## General Options

| Flag | Description | Default |
|------|-------------|---------|
| `--enable-oidc` | Enable OIDC | false |
| `--guacamole-version=X.X` | Guacamole version | 1.6.0 |
| `--guacamole-port=PORT` | Web UI port | 8080 |
| `--guacd-port=PORT` | guacd port | 4822 |
| `--api-session-timeout=TIME` | Timeout in Minuntes | 30 Mins |

## MySQL Options

| Flag | Description | Default |
|------|-------------|---------|
| `--mysql-version=X.X` | MySQL Version | 8.0 |
| `--mysql-database=NAME` | DB name | guacamole_db |
| `--mysql-user=NAME` | User | guac_user |
| `--mysql-port=PORT` | Port | 3306 |

## OIDC Options

| Flag | Description | Default |
|------|-------------|---------|
| `--oidc-tenant-id=ID` | Tenant ID | <id> |
| `--oidc-client-id=ID` | Client ID | <id> |
| `--oidc-redirect-uri=URI` | Callback | https://guacamole-public-url/ |
| `--extension-priority=list` | Load order | mysql, openid, ban |

## Secret Rotation

| Flag | Function |
|------|----------|
| `--rotate-all-secrets` | Rotate all |
| `--rotate-mysql-root-secret` | Rotate Root Password |
| `--rotate-mysql-user-secret` | Rotate User Password |
| `--rotate-oidc-client-secret` | Rotate OIDC Client Secret |

---

# 💾 State File Details

Location:
```
$HOME/.config/containers/systemd/guacamole/guacamole.state
```

Example:
```bash
bash deploy-guacamole-stack.sh
# gacamole-port will be set to default-port 8080
bash deploy-guacamole-stack.sh --guacamole-port=9000  
# state file will save this variable
bash deploy-guacamole-stack.sh
# uses port 9000 saved in state file
```
---

# 🧹 Reset Saved State

```bash
rm ~/.config/containers/systemd/guacamole/guacamole.state
```

---

# 🔐 Secret Management

List secrets:
```bash
podman secret ls
```

Secrets used:
- mysql-root-secret  
- mysql-user-secret  
- oidc-client-secret  

---

# 💾 Backup & Restore

## 📥 Backup
```bash
systemctl --user stop mysql

# Helper: get secret value (strip trailing newline)
get_secret() {   podman secret inspect --showsecret --format '{{.SecretData}}' "$1" | tr -d '\n'; }
# export secret
MYSQL_ROOT_PASSWORD="$(get_secret mysql-root-secret)"

# backup db
podman exec mysql mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" guacamole_db > ~/guacamole_db_backup.sql
```

## ♻️ Restore
```bash
# If podman-secret for mysql-root-password created already then use below
get_secret() {   podman secret inspect --showsecret --format '{{.SecretData}}' "$1" | tr -d '\n'; }
# export secret
MYSQL_ROOT_PASSWORD="$(get_secret mysql-root-secret)"

# if there is no podman-secret for mysql-root-password export it manually or directly use in command below
podman exec -i mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" guacamole_db < ~/guacamole_db_backup.sql

# restart mysql and guacamole quadlets
systemctl --user restart mysql guacamole
```

---

# 🛠 Systemd Commands

```bash
systemctl --user status guacamole
# check the status of guacamole
podman ps
# check all running containers
podman logs mysql
# check mysql logs
systemctl --user restart mysql guacd guacamole
# Restart containers
```

---

# ⬆️ Upgrade Instructions
```bash
bash deploy-guacamole-stack.sh --guacamole-version=X.X --mysql-version=X.X
```

---

# ❌ Full Uninstall

```bash
systemctl --user disable --now guacamole guacd mysql
rm -rf ~/.config/containers/systemd/guacamole/
podman secret rm mysql-root-secret mysql-user-secret oidc-client-secret
```