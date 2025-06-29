#!/usr/bin/env bash
set -euo pipefail

# Renkli çıktı fonksiyonları
print_success() { printf "\e[1;32m✓ %s\e[0m\n" "$@"; }
print_info() { printf "\e[1;36mℹ %s\e[0m\n" "$@"; }
print_warning() { printf "\e[1;33m⚠ %s\e[0m\n" "$@"; }
print_error() { printf "\e[1;31m✗ %s\e[0m\n" "$@" >&2; }

# Kök kontrolü
if [[ $EUID -ne 0 ]]; then
   print_error "Bu script root yetkileri ile çalıştırılmalıdır"
   exit 1
fi

# Log fonksiyonu
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a /var/log/diode-install.log >/dev/null
}

# Başlık
print_info "Diode Network Gateway Kurulumu Başlatılıyor..."
log "===== KURULUM BAŞLANGICI ====="

#############################
# 1) Gerekli Paketler
#############################
print_info "Güncellemeler kontrol ediliyor..."
sudo apt-get update -q

print_info "Gerekli paketler kuruluyor..."
sudo apt-get install -yq \
    unzip \
    curl \
    nginx \
    jq \
    net-tools \
    gnupg \
    software-properties-common

print_success "Paket kurulumu tamamlandı"

#############################
# 2) Nginx Ayarları
#############################
print_info "Nginx yapılandırması güncelleniyor..."

# Test sayfası oluştur
sudo bash -c 'cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Diode Gateway</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #2c3e50; }
        .status { 
            padding: 20px; 
            margin: 20px auto; 
            width: 60%; 
            border-radius: 5px;
            font-weight: bold;
        }
        .online { background-color: #2ecc71; color: white; }
        .diode-info { 
            background-color: #3498db; 
            color: white; 
            padding: 15px; 
            border-radius: 3px;
            margin-top: 30px;
            word-wrap: break-word;
        }
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
        fetch("/diode-info")
            .then(response => response.json())
            .then(data => {
                document.getElementById("diode-address").textContent = data.diode_address || "Bilinmiyor";
                document.getElementById("local-ip").textContent = data.local_ip || "Bilinmiyor";
            });
    </script>
</body>
</html>
EOF'

# Nginx port değişikliği
NGINX_CONF="/etc/nginx/sites-available/default"
if grep -q "listen 80" "$NGINX_CONF"; then
    sudo sed -i 's/listen 80 default_server;/listen 8888 default_server;/g' "$NGINX_CONF"
    sudo sed -i 's/listen \[::\]:80 default_server;/listen [::]:8888 default_server;/g' "$NGINX_CONF"
    print_success "Nginx portu 8888 olarak güncellendi"
else
    print_warning "Nginx zaten farklı bir portta çalışıyor"
fi

# Diode bilgi endpoint'i
sudo bash -c 'cat > /var/www/html/diode-info <<EOF
#!/bin/bash
echo "Content-type: application/json"
echo ""
echo "{"
echo "\"diode_address\":\"$(curl -s http://localhost:8080/address 2>/dev/null || echo "Hizmet başlatılıyor...")\","
echo "\"local_ip\":\"$(hostname -I | awk "{print \$1}")\""
echo "}"
EOF'

sudo chmod +x /var/www/html/diode-info
sudo systemctl restart nginx

#############################
# 3) Diode CLI Kurulumu
#############################
print_info "Diode CLI kuruluyor..."
INSTALL_DIR="/opt/diode"
sudo mkdir -p "$INSTALL_DIR"

# Sürüm kontrolü ile kurulum
LATEST_VERSION=$(curl -s https://api.github.com/repos/diodechain/diode_go_client/releases/latest | jq -r '.tag_name')
CURRENT_VERSION=$([ -f "$INSTALL_DIR/diode" ] && "$INSTALL_DIR/diode" version | awk '{print $3}' || echo "")

if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
    curl -sL "https://github.com/diodechain/diode_go_client/releases/download/${LATEST_VERSION}/diode_${LATEST_VERSION#v}_linux_amd64.zip" -o diode.zip
    sudo unzip -o diode.zip -d "$INSTALL_DIR" >/dev/null
    sudo rm diode.zip
    print_success "Diode CLI güncellendi: ${LATEST_VERSION}"
else
    print_info "En güncel sürüm zaten kurulu: ${CURRENT_VERSION}"
fi

# PATH güncellemesi
if ! grep -q "$INSTALL_DIR" /etc/profile; then
    echo "export PATH=${INSTALL_DIR}:\$PATH" | sudo tee /etc/profile.d/diode.sh >/dev/null
    source /etc/profile.d/diode.sh
fi

#############################
# 4) Systemd Servisi
#############################
print_info "Diode servisi yapılandırılıyor..."

# Eski servisleri temizle
sudo systemctl stop diode-publish.service 2>/dev/null || true
sudo systemctl disable diode-publish.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/diode-publish.service

# Yeni servis tanımı
sudo tee /etc/systemd/system/diode-publish.service >/dev/null <<EOF
[Unit]
Description=Diode HTTP Gateway Publisher
After=network.target nginx.service
Requires=nginx.service

[Service]
Type=exec
User=root
ExecStart=${INSTALL_DIR}/diode \\
    -diodeaddrs=eu1.prenet.diode.io:41046 \\
    -stats \\
    -verbose=1 \\
    publish -public 8888:80
Restart=always
RestartSec=10
Environment=PATH=${INSTALL_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=journal
StandardError=journal
SyslogIdentifier=diode-publish

# Güvenlik ayarları
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

# Servisi başlat
sudo systemctl daemon-reload
sudo systemctl enable --now diode-publish.service

#############################
# 5) Health Check
#############################
print_info "Servis sağlık kontrolü yapılıyor..."
sleep 5

if systemctl is-active --quiet diode-publish.service; then
    DIODE_ADDRESS=$(curl -s http://localhost:8080/address)
    print_success "Servis başarıyla başlatıldı"
    print_success "Yayın Adresi: https://${DIODE_ADDRESS}.diode.link"
else
    print_error "Servis başlatılamadı, loglar kontrol ediliyor"
    journalctl -u diode-publish.service -n 20 --no-pager
    exit 1
fi

#############################
# 6) Başarı Mesajı
#############################
cat <<EOF

$(printf "\e[1;42m KURULUM TAMAMLANDI \e[0m")
$(printf "\e[1;32m✔ Yerel sunucu başarıyla Diode Network'e bağlandı\e[0m")

$(printf "\e[1m🌐 Halka Açık URL:\e[0m")
   https://${DIODE_ADDRESS}.diode.link

$(printf "\e[1m📊 Durum Sayfası:\e[0m")
   http://$(hostname -I | awk '{print $1}') (Yerel ağ)

$(printf "\e[1m📋 Yönetim Komutları:\e[0m")
   Servis Durumu:  \e[32msudo systemctl status diode-publish.service\e[0m
   Logları Görüntüle: \e[33msudo journalctl -fu diode-publish.service\e[0m
   Servisi Yeniden Başlat: \e[36msudo systemctl restart diode-publish.service\e[0m

$(printf "\e[1m💡 Not:\e[0m") İlk bağlantı kurulumu 1-2 dakika sürebilir
EOF

log "===== KURULUM TAMAMLANDI ====="
