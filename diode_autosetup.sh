#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# Setup script for Diode HTTP Gateway Publisher with Nginx, systemd, TLS,
# health checks, parametric configuration, and security best practices
# ----------------------------------------------------------------------------

# If not root, re-exec with sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ Root yetkisi gerekiyor, sudo ile yeniden çalıştırılıyor..."
  exec sudo bash "$0" "$@"
fi

# Renkli çıktı fonksiyonları
print_success() { printf "\e[1;32m✓ %s\e[0m\n" "$@"; }
print_info()    { printf "\e[1;36mℹ %s\e[0m\n" "$@"; }
print_warning() { printf "\e[1;33m⚠ %s\e[0m\n" "$@"; }
print_error()   { printf "\e[1;31m✗ %s\e[0m\n" "$@" >&2; }

# Log fonksiyonu
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/diode-install.log >/dev/null
}

print_info "Diode Network Gateway Kurulumu Başlatılıyor..."
log "===== KURULUM BAŞLANGICI ====="

# Config paths
ENV_FILE="/etc/diode-publish/config.env"
NGINX_CONF="/etc/nginx/sites-available/diode_publish.conf"
SERVICE_FILE="/etc/systemd/system/diode-publish.service"
CLI_DIR="/opt/diode"

# Create config directory
mkdir -p "$(dirname "$ENV_FILE")"

# Generate environment file if missing
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<EOF
# Diode Publisher Configuration
LOCAL_PORT=8888
UPSTREAM_PORT=80
DIODE_ADDRS="eu1.prenet.diode.io:41046"
DOMAIN=""
DIODE_USER="diode"
EOF
  print_info "Oluşturuldu: $ENV_FILE"
fi

# Load config
source "$ENV_FILE"

# Ensure Diode user exists
if ! id -u "$DIODE_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$DIODE_USER"
  print_info "Kullanıcı oluşturuldu: $DIODE_USER"
fi

# Install prerequisites
PKGS=(unzip curl nginx certbot python3-certbot-nginx jq net-tools)
for pkg in "${PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    apt-get update -q
    apt-get install -yq "$pkg"
  fi
done
print_success "Gerekli paketler kuruldu"

# Configure Nginx
cat > "$NGINX_CONF" <<EOF
server {
  listen $LOCAL_PORT default_server;
  listen [::]:$LOCAL_PORT default_server;

  location /health {
    add_header Content-Type text/plain;
    return 200 'OK';
  }

  location / {
    proxy_pass http://127.0.0.1:$UPSTREAM_PORT;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/diode_publish.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
print_success "Nginx $LOCAL_PORT portuna ayarlandı"

# TLS if DOMAIN set\if [[ -n "$DOMAIN" ]]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
  systemctl reload nginx
  print_success "TLS sertifikası alındı: $DOMAIN"
fi

# Install Diode CLI
mkdir -p "$CLI_DIR"
chown "$DIODE_USER":"$DIODE_USER" "$CLI_DIR"
print_info "Diode CLI kuruluyor..."
VERSION=$(curl -sSf https://api.github.com/repos/diodechain/diode_go_client/releases/latest | jq -r '.tag_name' )
URL="https://github.com/diodechain/diode_go_client/releases/download/v${VERSION}/diode_linux_amd64.zip"
print_info "Sürüm $VERSION indiriliyor"
tmp=$(mktemp)
curl -fsSL "$URL" -o "$tmp"
unzip -o "$tmp" -d "$CLI_DIR"
chmod +x "$CLI_DIR/diode"
chown "$DIODE_USER":"$DIODE_USER" "$CLI_DIR/diode"
rm "$tmp"
print_success "Diode CLI yüklendi: $CLI_DIR/diode"

# Create systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Diode HTTP Gateway Publisher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$DIODE_USER
EnvironmentFile=$ENV_FILE
ExecStartPre=-/usr/bin/rm -rf /home/$DIODE_USER/.diode/chain
ExecStart=$CLI_DIR/diode -debug -diodeaddrs=\$DIODE_ADDRS publish -public \$LOCAL_PORT:\$UPSTREAM_PORT
Restart=on-failure
RestartSec=10
Environment=PATH=$CLI_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
enable_cmd="systemctl enable diode-publish.service"
start_cmd="systemctl start diode-publish.service"
eval \$enable_cmd && eval \$start_cmd
print_success "Servis etkinleştirildi ve başlatıldı"

print_info "Kurulum tamamlandı. Logları takip etmek için: journalctl -fu diode-publish.service"
