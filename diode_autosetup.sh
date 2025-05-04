#!/bin/bash

# 1. Gerekli paketleri yükle
sudo apt update && sudo apt install unzip curl tmux -y

# 2. Diode kurulumu
curl -Ssf https://diode.io/install.sh | bash

# 3. PATH ayarı (.bashrc'ye ekle ve anlık export yap)
if ! grep -q '/root/opt/diode' /root/.bashrc; then
    echo 'export PATH=/root/opt/diode:$PATH' >> /root/.bashrc
fi
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

# 7. Kurulum tamamlandı mesajı ve tmux komutlarını göster
echo ""
echo "✅ Kurulum tamamlandı!"
echo ""
echo "📌 Tmux ile başlatmak için aşağıdaki adımları izleyin:"
echo ""
echo "1. Tmux oturumu başlat:"
echo "   tmux new -s diode"
echo ""
echo "2. Scripti başlat:"
echo "   /root/diode-autopublish.sh"
echo ""
echo "3. Oturumdan çıkmak (çalışmaya devam ederken):"
echo "   CTRL + B tuşlarına basın, ardından D tuşuna basın (detach)"
echo ""
echo "4. Tekrar girmek için:"
echo "   tmux attach -t diode"
echo ""
echo "Kurulum tamamen bitti ve tmux ile çalıştırmaya hazır."
