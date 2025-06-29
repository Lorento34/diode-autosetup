#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# Setup script for Diode HTTP Gateway Publisher with Nginx, systemd, TLS,
# health checks, parametric configuration, and security best practices
# ----------------------------------------------------------------------------

# Default configuration
ENV_FILE="/etc/diode-publish/config.env"
NGINX_CONF="/etc/nginx/sites-available/diode_publish.conf"
SERVICE_FILE="/etc/systemd/system/diode-publish.service"

# Create config directory
sudo mkdir -p "$(dirname "$ENV_FILE")"

# Generate environment file if missing
if [[ ! -f "$ENV_FILE" ]]; then
  sudo tee "$ENV_FILE" > /dev/null <<EOF
# Diode Publisher Configuration
# Local port where Nginx listens
LOCAL_PORT=8888
# Upstream port Nginx proxies to (your internal service)
UPSTREAM_PORT=80
# Diode server addresses
DIODE_ADDRS="eu1.prenet.diode.io:41046"
# Domain for TLS (optional)
DOMAIN=""
# Diode user
DIODE_USER="diode"
EOF
  echo "Created default config at $ENV_FILE"
fi

# Load configuration
source "$ENV_FILE"

# Ensure Diode user exists
if ! id -u "$DIODE_USER" &>/dev/null; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$DIODE_USER"
  echo "Created system user: $DIODE_USER"
fi

# Install prerequisites if missing
PKGS=("unzip" "curl" "nginx" "certbot" "python3-certbot-nginx")
for pkg in "${PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y "$pkg"
  fi
done

# Configure Nginx site
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
  listen $LOCAL_PORT default_server;
  listen [::]:$LOCAL_PORT default_server;

  # Health endpoint
  location /health {
    add_header Content-Type text/plain;
    return 200 'OK';
  }

  # Proxy to internal service
  location / {
    proxy_pass http://127.0.0.1:$UPSTREAM_PORT;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

# Enable site
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/diode_publish.conf
# Disable default site if still enabled
sudo rm -f /etc/nginx/sites-enabled/default

# Reload Nginx
sudo nginx -t && sudo systemctl reload nginx

echo "🖥️  Nginx configured and reloaded listening on port $LOCAL_PORT"

# Optional TLS via Certbot
if [[ -n "$DOMAIN" ]]; then
  echo "🔐 Obtaining TLS certificates for $DOMAIN"
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
  sudo systemctl reload nginx
  echo "✅ TLS configured for $DOMAIN"
fi

# Install Diode CLI for diode user
CLI_DIR="/opt/diode"
if [[ ! -x "$CLI_DIR/diode" ]]; then
  sudo mkdir -p "$CLI_DIR"
  sudo chown "$DIODE_USER":"$DIODE_USER" "$CLI_DIR"
  sudo -u "$DIODE_USER" bash -c "curl -sSf https://diode.io/install.sh | DIODE_HOME=$CLI_DIR bash"
  sudo chmod +x "$CLI_DIR/diode"
  echo "⚙️  Diode CLI installed at $CLI_DIR"
fi

# Create systemd service
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Diode HTTP Gateway Publisher (custom relay)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$DIODE_USER
EnvironmentFile=$ENV_FILE
ExecStartPre=/usr/bin/curl --fail http://localhost:\$LOCAL_PORT/health
ExecStart=$CLI_DIR/diode -debug -diodeaddrs=\$DIODE_ADDRS publish -public \$LOCAL_PORT:\$UPSTREAM_PORT
Restart=on-failure
RestartSec=10
Environment=PATH=$CLI_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable --now diode-publish.service

echo "✅ Diode publish service enabled and started"
echo "🔍 Check logs: sudo journalctl -fu diode-publish.service"
