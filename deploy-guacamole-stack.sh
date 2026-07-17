#!/bin/bash

set -e

# -----------------------------------------------------------
# Rotation + feature flags (defaults; may be overridden by state/CLI)
# -----------------------------------------------------------
ENABLE_OIDC=false

ROTATE_ALL_SECRETS=false
ROTATE_MYSQL_ROOT_SECRET=false
ROTATE_MYSQL_USER_SECRET=false
ROTATE_OIDC_CLIENT_SECRET=false

# -----------------------------------------------------------
# Paths
# -----------------------------------------------------------
CONFIG_DIR="$HOME/.config/containers/systemd/guacamole"
MYSQL_DATA_DIR="$CONFIG_DIR/mysql-data"

mkdir -p "$CONFIG_DIR" "$MYSQL_DATA_DIR"

# -----------------------------------------------------------
# State file for persisting last-used non-secret values
# -----------------------------------------------------------
STATE_FILE="$CONFIG_DIR/guacamole.state"

# Load previous values if present (so they can override hardcoded defaults)
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

# -----------------------------------------------------------
# Helper: check if Podman secret exists
# -----------------------------------------------------------
secret_exists() {
  podman secret inspect "$1" >/dev/null 2>&1
}

# Helper: get secret value (strip trailing newline)
get_secret() {
  podman secret inspect --showsecret --format '{{.SecretData}}' "$1" | tr -d '\n'
}

# -----------------------------------------------------------
# 1. Parse command-line arguments (override state/defaults)
# -----------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --enable-oidc) ENABLE_OIDC=true ;;

    --oidc-tenant-id=*) OIDC_TENANT_ID="${arg#*=}" ;;
    --oidc-client-id=*) OIDC_CLIENT_ID="${arg#*=}" ;;
    --oidc-redirect-uri=*) OIDC_REDIRECT_URI="${arg#*=}" ;;
    --extension-priority=*) EXTENSION_PRIORITY="${arg#*=}" ;;

    --guacamole-version=*) GUACAMOLE_VERSION="${arg#*=}" ;;
    --guacamole-port=*) GUACAMOLE_PORT="${arg#*=}" ;;
    --guacd-port=*) GUACD_PORT="${arg#*=}" ;;
    --api-session-timeout=*) API_SESSION_TIMEOUT="${arg#*=}" ;;

    --mysql-version=*) MYSQL_VERSION="${arg#*=}" ;;
    --mysql-database=*) MYSQL_DATABASE="${arg#*=}" ;;
    --mysql-user=*) MYSQL_USER="${arg#*=}" ;;
    --mysql-port=*) MYSQL_PORT="${arg#*=}" ;;

    --rotate-all-secrets) ROTATE_ALL_SECRETS=true ;;
    --rotate-mysql-root-secret) ROTATE_MYSQL_ROOT_SECRET=true ;;
    --rotate-mysql-user-secret) ROTATE_MYSQL_USER_SECRET=true ;;
    --rotate-oidc-client-secret) ROTATE_OIDC_CLIENT_SECRET=true ;;
  esac
done

# If rotate-all is set, rotate each specific secret
if [ "$ROTATE_ALL_SECRETS" = true ]; then
  ROTATE_MYSQL_ROOT_SECRET=true
  ROTATE_MYSQL_USER_SECRET=true
  ROTATE_OIDC_CLIENT_SECRET=true
fi

# -----------------------------------------------------------
# 2. Defaults for non-sensitive values
#    Precedence: CLI > state file > these defaults
# -----------------------------------------------------------
GUACAMOLE_VERSION=${GUACAMOLE_VERSION-1.6.0}
GUACAMOLE_PORT=${GUACAMOLE_PORT-8080}
GUACD_PORT=${GUACD_PORT-4822}
API_SESSION_TIMEOUT=${API_SESSION_TIMEOUT-30}

MYSQL_VERSION=${MYSQL_VERSION-8.0}
MYSQL_DATABASE=${MYSQL_DATABASE-guacamole_db}
MYSQL_USER=${MYSQL_USER-guacamole_user}
MYSQL_PORT=${MYSQL_PORT-3306}

OIDC_TENANT_ID=${OIDC_TENANT_ID-guacamole-sso-tenant-id}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID-guacamole-sso-app-client}
OIDC_REDIRECT_URI=${OIDC_REDIRECT_URI-https://guacamole-public-url/}

EXTENSION_PRIORITY=${EXTENSION_PRIORITY-"mysql, openid, ban"}

# -----------------------------------------------------------
# 2b. Persist final non-secret values for next run
# -----------------------------------------------------------
save_state() {
  {
    echo "ENABLE_OIDC=$(printf '%q' "$ENABLE_OIDC")"

    echo "GUACAMOLE_VERSION=$(printf '%q' "$GUACAMOLE_VERSION")"
    echo "GUACAMOLE_PORT=$(printf '%q' "$GUACAMOLE_PORT")"
    echo "GUACD_PORT=$(printf '%q' "$GUACD_PORT")"

    echo "MYSQL_VERSION=$(printf '%q' "$MYSQL_VERSION")"
    echo "MYSQL_DATABASE=$(printf '%q' "$MYSQL_DATABASE")"
    echo "MYSQL_USER=$(printf '%q' "$MYSQL_USER")"
    echo "MYSQL_PORT=$(printf '%q' "$MYSQL_PORT")"

    echo "OIDC_TENANT_ID=$(printf '%q' "$OIDC_TENANT_ID")"
    echo "OIDC_CLIENT_ID=$(printf '%q' "$OIDC_CLIENT_ID")"
    echo "OIDC_REDIRECT_URI=$(printf '%q' "$OIDC_REDIRECT_URI")"

    echo "EXTENSION_PRIORITY=$(printf '%q' "$EXTENSION_PRIORITY")"
  } > "$STATE_FILE"
}

# Save state immediately after resolving values
save_state

# -----------------------------------------------------------
# 3. Manage secrets (create or rotate)
# -----------------------------------------------------------

# MySQL root secret
if secret_exists mysql-root-secret && [ "$ROTATE_MYSQL_ROOT_SECRET" = false ]; then
  echo "🔐 Using existing Podman secret: mysql-root-secret"
else
  if secret_exists mysql-root-secret && [ "$ROTATE_MYSQL_ROOT_SECRET" = true ]; then
    echo "♻️ Rotating secret: mysql-root-secret"
    podman secret rm mysql-root-secret >/dev/null 2>&1 || true
  fi
  read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
  echo
  echo -n "$MYSQL_ROOT_PASSWORD" | podman secret create mysql-root-secret - >/dev/null
  echo "✅ Created Podman secret: mysql-root-secret"
fi

# MySQL user secret
if secret_exists mysql-user-secret && [ "$ROTATE_MYSQL_USER_SECRET" = false ]; then
  echo "🔐 Using existing Podman secret: mysql-user-secret"
else
  if secret_exists mysql-user-secret && [ "$ROTATE_MYSQL_USER_SECRET" = true ]; then
    echo "♻️ Rotating secret: mysql-user-secret"
    podman secret rm mysql-user-secret >/dev/null 2>&1 || true
  fi
  read -s -p "Enter MySQL user password: " MYSQL_PASSWORD
  echo
  echo -n "$MYSQL_PASSWORD" | podman secret create mysql-user-secret - >/dev/null
  echo "✅ Created Podman secret: mysql-user-secret"
fi

# OIDC client secret
if [ "$ENABLE_OIDC" = true ]; then
  if secret_exists oidc-client-secret && [ "$ROTATE_OIDC_CLIENT_SECRET" = false ]; then
    echo "🔐 Using existing Podman secret: oidc-client-secret"
  else
    if secret_exists oidc-client-secret && [ "$ROTATE_OIDC_CLIENT_SECRET" = true ]; then
      echo "♻️ Rotating secret: oidc-client-secret"
      podman secret rm oidc-client-secret >/dev/null 2>&1 || true
    fi
    read -s -p "Enter OIDC client secret: " OIDC_CLIENT_SECRET
    echo
    echo -n "$OIDC_CLIENT_SECRET" | podman secret create oidc-client-secret - >/dev/null
    echo "✅ Created Podman secret: oidc-client-secret"
  fi
fi

# -----------------------------------------------------------
# 4. Prepare Secret= line for guacamole.container
# -----------------------------------------------------------
OIDC_SECRET_LINE=""
if [ "$ENABLE_OIDC" = true ]; then
  OIDC_SECRET_LINE='Secret=oidc-client-secret,type=env,target=OPENID_CLIENT_SECRET'
fi

# -----------------------------------------------------------
# 5. Generate MySQL quadlet
# -----------------------------------------------------------
cat > "$CONFIG_DIR/mysql.container" <<EOF
[Unit]
Description=MySQL for Guacamole

[Container]
ContainerName=mysql
Image=docker.io/library/mysql:$MYSQL_VERSION
Network=host

Environment="MYSQL_DATABASE=$MYSQL_DATABASE"
Environment="MYSQL_USER=$MYSQL_USER"
Environment="MYSQL_PORT=$MYSQL_PORT"

Secret=mysql-root-secret,type=env,target=MYSQL_ROOT_PASSWORD
Secret=mysql-user-secret,type=env,target=MYSQL_PASSWORD

Volume=$MYSQL_DATA_DIR:/var/lib/mysql:Z
PublishPort=$MYSQL_PORT

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# -----------------------------------------------------------
# 6. Generate guacd quadlet
# -----------------------------------------------------------
cat > "$CONFIG_DIR/guacd.container" <<EOF
[Unit]
Description=Guacamole Proxy Daemon (guacd)

[Container]
ContainerName=guacd
Image=docker.io/guacamole/guacd:$GUACAMOLE_VERSION
Network=host
PublishPort=$GUACD_PORT

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# -----------------------------------------------------------
# 7. Generate Guacamole quadlet
# -----------------------------------------------------------
cat > "$CONFIG_DIR/guacamole.container" <<EOF
[Unit]
Description=Apache Guacamole Web Application

[Container]
ContainerName=guacamole
Image=docker.io/guacamole/guacamole:$GUACAMOLE_VERSION
Network=host
PublishPort=$GUACAMOLE_PORT

Environment="WEBAPP_CONTEXT=ROOT"
Environment="API_SESSION_TIMEOUT=$API_SESSION_TIMEOUT"
# ---- guacd ---- #
Environment="GUACD_HOSTNAME=127.0.0.1"
Environment="GUACD_PORT=$GUACD_PORT"
Environment="GUACD_TIMEOUT=300"  # 5 min idle drop
# ---- connection limits ---- #
Environment="MYSQL_DEFAULT_MAX_CONNECTIONS=2"
Environment="MYSQL_DEFAULT_MAX_CONNECTIONS_PER_USER=1"
Environment="MYSQL_ABSOLUTE_MAX_CONNECTIONS=20"
# ---- mysql ---- #
Environment="MYSQL_HOSTNAME=127.0.0.1"
Environment="MYSQL_PORT=$MYSQL_PORT"
Environment="MYSQL_DATABASE=$MYSQL_DATABASE"
Environment="MYSQL_USER=$MYSQL_USER"
Environment="MYSQL_AUTO_CREATE_ACCOUNTS=true"
# ---- OIDC ---- #
Environment="AUTH_PROVIDER=net.sourceforge.guacamole.net.auth.openid.OpenIDAuthenticationProvider"
Environment="OPENID_ENABLED=true"
Environment="OPENID_AUTHORIZATION_ENDPOINT=https://login.microsoftonline.com/$OIDC_TENANT_ID/oauth2/v2.0/authorize"
Environment="OPENID_JWKS_ENDPOINT=https://login.microsoftonline.com/$OIDC_TENANT_ID/discovery/v2.0/keys"
Environment="OPENID_ISSUER=https://login.microsoftonline.com/$OIDC_TENANT_ID/v2.0"
Environment="OPENID_CLIENT_ID=$OIDC_CLIENT_ID"
Environment="OPENID_REDIRECT_URI=$OIDC_REDIRECT_URI"
Environment="OPENID_SCOPE=openid profile email"
Environment="OPENID_GROUPS_CLAIM_TYPE=groups"

Environment="EXTENSION_PRIORITY=$EXTENSION_PRIORITY"

Secret=mysql-user-secret,type=env,target=MYSQL_PASSWORD
$OIDC_SECRET_LINE

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# -----------------------------------------------------------
# 8. Enable and Start services
# -----------------------------------------------------------

echo "🔄 Reloading systemd user daemon…"
systemctl --user daemon-reexec || true
systemctl --user daemon-reload

echo "🚀 Enabling Quadlet units…"
systemctl --user enable --now mysql 2>/dev/null || echo "ℹ️  enabled mysql"
systemctl --user enable --now guacd 2>/dev/null || echo "ℹ️  enabled guacd"
systemctl --user enable --now guacamole 2>/dev/null || echo "ℹ️  enabled guacamole"

echo "🚀 Starting containers via systemd…"
systemctl --user start mysql || true
systemctl --user start guacd || true
systemctl --user start guacamole || true

# -----------------------------------------------------------
# 9. Wait for MySQL (using secret)
# -----------------------------------------------------------
echo "⏳ Waiting for MySQL…"
MYSQL_ROOT_PASSWORD="$(get_secret mysql-root-secret)"

for i in {1..30}; do
  if podman exec mysql mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping --silent 2>/dev/null; then
    echo "✅ MySQL is ready."
    break
  fi
  sleep 2
done
# Extra wait for stability
sleep 15

# -----------------------------------------------------------
# 10. Initialize DB
# -----------------------------------------------------------
echo "🛠 Initializing Guacamole DB schema..."
INIT_SQL="$CONFIG_DIR/initdb.sql"

podman run --rm docker.io/guacamole/guacamole:$GUACAMOLE_VERSION \
  /opt/guacamole/bin/initdb.sh --mysql > "$INIT_SQL" || true

if [ -f "$INIT_SQL" ]; then
  podman exec -i mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" < "$INIT_SQL" \
    && echo "✅ Guacamole DB schema imported." \
    || echo "⚠️ Schema import may have already been done."
else
  echo "❌ initdb.sql missing"
fi

rm -f "$INIT_SQL"

systemctl --user restart mysql guacamole || true

echo
echo "🎉 Deployment complete!"
echo "➡️ http://<host-ip>:$GUACAMOLE_PORT/"
echo "🔐 Podman secrets:"
echo "    - mysql-root-secret"
echo "    - mysql-user-secret"
[ "$ENABLE_OIDC" = true ] && echo "    - oidc-client-secret"