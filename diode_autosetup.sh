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

# 5. Autopublish script'ini oluştur
cat <<EOF | sudo tee /root/diode-autopublish.sh > /dev/null
#!/bin/bash
export PATH=/root/opt/diode:\$PATH

while true; do
    echo "[\$(date)] Diode publish başlatılıyor..."
    diode -diodeaddrs=${SERVER_IP}:41046 -debug publish -public 8888:80
    echo "[\$(date)] 5 dakika bekleniyor..."
    sleep 300
done
EOF
sudo chmod +x /root/diode-autopublish.sh

# 6. systemd servis birimini oluştur
cat <<EOF | sudo tee /etc/systemd/system/diode-autopublish.service > /dev/null
[Unit]
Description=Diode Auto-Publish Service
After=network.target

[Service]
Type=simple
Environment="PATH=/root/opt/diode:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/diode-autopublish.sh
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
echo -e "\e[1m✅Kurulum ve service konfigürasyonu tamamlandı! Kullanabileceğiniz komutlar aşağıdadır.\e[0m"
echo ""
echo -e "\e[1m🔍Gerçek zamanlı servis loglarını görmek için: \e[1;32msudo journalctl -fu diode-autopublish.service\e[0m"
echo ""
echo -e "\e[1m🖥️ Servis durumunu kontrol etmek için: \e[1;35msudo systemctl status diode-autopublish.service\e[0m"
echo ""
echo -e "\e[1m🛠️ Restart atmak için: \e[1;33msudo systemctl restart diode-autopublish.service\e[0m"
echo ""
