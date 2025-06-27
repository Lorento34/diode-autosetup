#!/bin/bash
set -e

#############################
# 1) Gerekli paketler
#############################
sudo apt update
sudo apt install -y unzip curl nginx

#############################
# 2) Nginx’i 8888 portuna taşı
#############################
sudo sed -i 's/listen 80 default_server;/listen 8888 default_server;/g' /etc/nginx/sites-available/default
sudo sed -i 's/listen \[::\]:80 default_server;/listen [::]:8888 default_server;/g' /etc/nginx/sites-available/default
sudo systemctl restart nginx

#############################
# 3) Diode CLI kurulumu
#############################
curl -Ssf https://diode.io/install.sh | bash

if ! grep -q '/root/opt/diode' /root/.bashrc; then
    echo 'export PATH=/root/opt/diode:$PATH' >> /root/.bashrc
fi
export PATH=/root/opt/diode:$PATH

#############################
# 4) Eski “autopublish” kalıntılarını temizle
#############################
sudo systemctl disable --now diode-autopublish.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/diode-autopublish.service
sudo rm -rf /opt/diode-publisher

#############################
# 5) Yeni, sade systemd servisini oluştur
#############################
cat <<'EOF' | sudo tee /etc/systemd/system/diode-publish.service > /dev/null
[Unit]
Description=Diode HTTP Gateway Publisher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/root/opt/diode/diode -debug publish -public 8888:80
Restart=on-failure
RestartSec=10
Environment=PATH=/root/opt/diode:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

#############################
# 6) Servisi etkinleştir & başlat
#############################
sudo systemctl daemon-reload
sudo systemctl enable --now diode-publish.service

#############################
# 7) Bilgilendirme
#############################
echo ""
printf "\e[1m✅ Kurulum tamamlandı. Yayın adresinizi birkaç saniye içinde loglarda göreceksiniz.\e[0m\n\n"
printf "\e[1m🔍 Logları izlemek için:\e[0m \e[32msudo journalctl -fu diode-publish.service\e[0m\n"
printf "\e[1m🛠️  Yeniden başlatmak için:\e[0m \e[33msudo systemctl restart diode-publish.service\e[0m\n"
printf "\e[1m🖥️  Durum kontrolü:\e[0m \e[35msudo systemctl status diode-publish.service\e[0m\n\n"
