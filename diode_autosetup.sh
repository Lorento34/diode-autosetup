#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# Diode Network Gateway Kurulumu Scripti
# ----------------------------------------------------------------------------

# Renkli çıktı fonksiyonları
print_success() { printf "\e[1;32m✓ %s\e[0m\n" "$@"; }
print_info()    { printf "\e[1;36mℹ %s\e[0m\n" "$@"; }
print_warning() { printf "\e[1;33m⚠ %s\e[0m\n" "$@"; }
print_error()   { printf "\e[1;31m✗ %s\e[0m\n" "$@" >&2; }

# Kök kontrolü
if [ "$(id -u)" -ne 0 ]; then
    print_error "Bu script root yetkileri ile çalıştırılmalıdır"
    exit 1
fi

# Log fonksiyonu
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/diode-install.log >/dev/null
}

print_info "Diode Network Gateway Kurulumu Başlatılıyor..."
log "===== KURULUM BAŞLANGICI ====="

#############################
# 1) Gerekli Paketler
#############################
print_info "Paket listesi güncelleniyor..."
apt-get update -q

print_info "Gerekli paketler kuruluyor..."
apt-get install -yq unzip curl nginx jq net-tools

print_success "Paket kurulumu tamamlandı"

#############################
# 2) Nginx Ayarları
#############################
print_info "Nginx yapılandırması güncelleniyor..."

# Statik test sayfası
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Diode Gateway</title>
  <style>
    body { font-family:Arial,sans-serif; text-align:center; padding:50px; }
    h1 { color:#2c3e50; }
    .status { padding:20px; margin:20px auto; width:60%; border-radius:5px; font-weight:bold; }
    .online { background-color:#2ecc71; color:white; }
    .diode-info { background-color:#3498db; color:white; padding:15px; border-radius:3px; margin-top:30px; word-wrap:break-word; }
  </style>
</head>
<body>
  <h1>Diode Network Gateway</h1>
  <p>Bu sunucu Diode Network üzerinden yayın yapmaktadır</p>
  <div class="status online">ÇALIŞIYOR</div>
  <div class="diode-info">
    <p><strong>Yayın Adresi:</strong> <span id="diode-address">Yükleniyor...</span></p>
    <p><strong>Yerel IP:</strong> <span id="local-ip">Yükleniyor...</span></p>
  </div>
  <script>
    fetch('/diode-info')
      .then(r=>r.json())
      .then(d=>{
        document.getElementById('diode-address').textContent=d.diode_address||'Bilinmiyor';
        document.getElementById('local-ip').textContent=d.local_ip||'Bilinmiyor';
      });
  </script>
</body>
</html>
EOF

# Portu 8888'e taşı
NGINX_CONF="/etc/nginx/sites-available/default"
if grep -q "listen 80" "$NGINX_CONF"; then
  sed -i 's/listen 80 default_server;/listen 8888 default_server;/'  "$NGINX_CONF"
  sed -i 's/listen \[::\]:80 default_server;/listen [::]:8888 default_server;/' "$NGINX_CONF"
  print_success "Nginx portu 8888 olarak güncellendi"
else
  print_warning "Nginx zaten farklı bir portta çalışıyor"
fi

# /diode-info endpoint
cat > /var/www/html/diode-info <<'EOF'
#!/usr/bin/env bash
echo 'Content-Type: application/json'
echo
echo '{'
echo '  "diode_address": "'$(curl -s http://localhost:8080/address 2>/dev/null || echo 'Başlatılıyor...')'",'
echo '  "local_ip": "'$(hostname -I | awk '{print $1}')'"'
echo '}'
EOF
chmod +x /var/www/html/diode-info

nginx -t && systemctl restart nginx
print_success "Nginx yeniden başlatıldı ve test edildi"

#############################
# 3) Diode CLI Kurulumu
#############################
print_info "Diode CLI kuruluyor..."
INSTALL_DIR="/opt/diode"
mkdir -p "$INSTALL_DIR"

# GitHub API’dan son sürümü çek
LATEST_VERSION=$(curl -s https://api.github.com/repos/diodechain/diode_go_client/releases/latest \
  | jq -r '.tag_name // empty')

if [ -n "$LATEST_VERSION" ]; then
  DOWNLOAD_URL="https://github.com/diodechain/diode_go_client/releases/download/${LATEST_VERSION}/diode_linux_amd64.zip"
  print_info "Sürüm $LATEST_VERSION bulundu, indiriliyor..."
else
  print_warning "Son sürüm bulunamadı, fallback indiriliyor..."
  DOWNLOAD_URL="https://github.com/diodechain/diode_go_client/releases/latest/download/diode_linux_amd64.zip"
fi

curl -fL "$DOWNLOAD_URL" -o diode.zip || { print_error "Diode indirme başarısız"; exit 1; }
unzip -o diode.zip -d "$INSTALL_DIR"  || { print_error "ZIP açılamadı"; exit 1; }
rm -f diode.zip
chmod +x "${INSTALL_DIR}/diode"
print_success "Diode CLI kuruldu"

# PATH’e ekle
if ! grep -q "$INSTALL_DIR" /etc/profile.d/diode.sh 2>/dev/null; then
  echo "export PATH=${INSTALL_DIR}:\$PATH" > /etc/profile.d/diode.sh
fi

#############################
# 4) systemd Servisi
#############################
print_info "Systemd servisi oluşturuluyor..."

SERVICE_FILE="/etc/systemd/system/diode-publish.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Diode HTTP Gateway Publisher
After=network-online.target nginx.service
Requires=nginx.service

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/diode \\
    -diodeaddrs=eu1.prenet.diode.io:41046 \\
    publish -public 8888:80
Restart=on-failure
RestartSec=10
Environment=PATH=${INSTALL_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=journal
StandardError=journal
SyslogIdentifier=diode-publish

NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes
PrivateDevices=yes
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now diode-publish.service
print_success "Service başlatıldı"

#############################
# 5) Health Check
#############################
print_info "Servis sağlığı kontrol ediliyor..."
sleep 5
if systemctl is-active --quiet diode-publish.service; then
  DIODE_ADDRESS=$(curl -s http://localhost:8080/address || echo "adres-alınamadı")
  print_success "Servis ayakta"
  print_success "Yayın URL: https://${DIODE_ADDRESS}.diode.link"
else
  print_error "Servis başlatılamadı. Son loglar:"
  journalctl -u diode-publish.service -n20 --no-pager
  exit 1
fi

#############################
# 6) Sonuç
#############################
cat <<EOF

\e[1;42m KURULUM TAMAMLANDI! \e[0m

✔ Yerel sunucu başarıyla Diode Network’e bağlandı

🌐 Halka Açık URL:
   https://${DIODE_ADDRESS}.diode.link

📊 Durum Sayfası (Yerel Ağ):
   http://$(hostname -I | awk '{print $1}')

📋 Yönetim Komutları:
   Servis Durumu:      sudo systemctl status diode-publish.service
   Logları Görüntüle:  sudo journalctl -fu diode-publish.service
   Yeniden Başlat:     sudo systemctl restart diode-publish.service

💡 Not: İlk yayın adresinin oluşması 1-2 dakika sürebilir

EOF

log "===== KURULUM TAMAMLANDI ====="
