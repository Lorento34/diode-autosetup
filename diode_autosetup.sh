#!/bin/bash

# 1. Gerekli paketleri yükle
sudo apt update && sudo apt install unzip curl -y

# 2. Diode kurulumu
curl -Ssf https://diode.io/install.sh | bash

# 3. PATH ayarı
echo 'export PATH=/root/opt/diode:$PATH' >> /root/.bashrc
export PATH=/root/opt/diode:$PATH

# 4. Sunucu IP'sini alma
SERVER_IP=$(hostname -I | awk '{print $1}')

# 5. diode-autopublish.sh dosyasını oluştur
cat <<EOF > /root/diode-autopublish.sh
#!/bin/bash
export PATH=/root/opt/diode:\$PATH

while true; do
    echo "[\$(date)] Diode publish başlatılıyor..."
    diode -diodeaddrs=$SERVER_IP:41046 -debug publish -public 8888:80
    echo "[\$(date)] 5 dakika bekleniyor..."
    sleep 300
done
EOF

# 6. Çalıştırılabilir yap
chmod +x /root/diode-autopublish.sh

echo "Kurulum tamamlandı. Tmux içinde aşağıdaki komutu kullanarak başlatabilirsiniz:"
echo ""
echo "tmux new -s diode"
echo "/root/diode-autopublish.sh"
echo ""
echo "Çıkmak için CTRL+B tuşuna basıp ardından D tuşuna basın (detach için)."
