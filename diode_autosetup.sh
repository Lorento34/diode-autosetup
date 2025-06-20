#!/bin/bash
set -e

# 1. Gerekli paketleri yükle
sudo apt update && sudo apt install -y unzip curl

# 2. Diode CLI kurulumu
curl -Ssf https://diode.io/install.sh | bash

# 3. PATH ayarını hem geçerli oturuma hem de .bashrc'ye ekle
if ! grep -q '/root/opt/diode' /root/.bashrc; then
    echo 'export PATH=/root/opt/diode:$PATH' >> /root/.bashrc
fi
export PATH=/root/opt/diode:$PATH

# 4. Sunucu IP'sini al
SERVER_IP=$(hostname -I | awk '{print $1}')

# 5. /opt/diode-publisher dizinini oluştur ve publish script'ini yerleştir
sudo mkdir -p /opt/diode-publisher

cat <<EOF | sudo tee /opt/diode-publisher/diode-autopublish.sh > /dev/null
#!/bin/bash
export PATH=/root/opt/diode:\$PATH

while true; do
    echo "[\$(date)] Diode publish başlatılıyor..."
    diode -diodeaddrs=${SERVER_IP}:41046 -debug publish -public 8888:80
    echo "[\$(date)] 5 dakika bekleniyor..."
    sleep 300
done
EOF

sudo chmod +x /opt/diode-publisher/diode-autopublish.sh

# 6. systemd servis birimini oluştur
cat <<EOF | sudo tee /etc/systemd/system/diode-autopublish.service > /dev/null
[Unit]
Description=Diode Auto-Publish Service
After=network.target

[Service]
Type=simple
Environment="PATH=/root/opt/diode:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/diode-publisher/diode-autopublish.sh
Restart=on-failure
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF

# 7. systemd'i yeniden yükle, servisi aktif et ve başlat
sudo systemctl daemon-reload
sudo systemctl enable diode-autopublish.service
sudo systemctl start diode-autopublish.service

echo ""
echo ""
printf "\e[1m✅ Kurulum ve service konfigürasyonu tamamlandı! Kullanabileceğiniz komutlar aşağıdadır.\e[0m\n"
echo ""
printf "\e[1m🔍\x20Gerçek zamanlı servis loglarını görmek için:\e[0m \e[1;32msudo journalctl -fu diode-autopublish.service\e[0m\n"
echo ""
printf "\e[1m🖥️\x20 Servis durumunu kontrol etmek için:\e[0m \e[1;35msudo systemctl status diode-autopublish.service\e[0m\n"
echo ""
printf "\e[1m🛠️\x20 Restart atmak için:\e[0m \e[1;33msudo systemctl restart diode-autopublish.service\e[0m\n"
echo ""
