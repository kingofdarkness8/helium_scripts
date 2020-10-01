#!/bin/bash

# Welcome!
# Just want to get a few things out of the way. This script assumes you're running this on a raspberry pi 4 with raspberian lite freshly installed.

# Check if root
if [ "$(whoami)" != "root" ]; then
  whiptail --msgbox "Sorry you are not root. You must type: sudo sh install.sh" $WT_HEIGHT $WT_WIDTH
  exit
fi

# Check if raspi-config is installed
if [ $(dpkg-query -W -f='${Status}' raspi-config 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
  whiptail --msgbox "Raspi-config is already installed, try upgrading it within raspi-config..." 10 60
else
  wget https://archive.raspberrypi.org/debian/pool/main/r/raspi-config/raspi-config_20200902_all.deb -P /tmp
  apt-get install libnewt0.52 whiptail parted triggerhappy lua5.1 alsa-utils -y
  # Auto install dependancies on eg. ubuntu server on RPI
  apt-get install -fy
  dpkg -i /tmp/raspi-config_20200902_all.deb
  whiptail --msgbox "Raspi-config is now installed, run it by typing: sudo raspi-config" 10 60
fi

sudo apt update -y
sudo apt upgrade -y

#with docker.io command
#sudo apt install curl jq docker.io git vim gcc build-essential -y

#without docker.io command
sudo apt install curl jq git vim nano gcc build-essential -y

sudo usermod -aG docker pi

mkdir ~/miner_data

cd ~
git clone https://github.com/Lora-net/packet_forwarder
git clone https://github.com/Lora-net/lora_gateway

cd packet_forwarder/lora_pkt_fwd

mv ~/packet_forwarder/lora_pkt_fwd/global_conf.json ~/packet_forwarder/lora_pkt_fwd/global_conf.json.1
curl -s -o ~/packet_forwarder/lora_pkt_fwd/global_conf.json 'https://helium-media.s3-us-west-2.amazonaws.com/global_conf.json'
#wget https://helium-media.s3-us-west-2.amazonaws.com/global_conf.json --backups

#sed link
sed -i 's/#define SPI_SPEED       8000000/#define SPI_SPEED       2000000/' /home/pi/lora_gateway/libloragw/src/loragw_spi.native.c

cd /home/pi/packet_forwarder/
./compile.sh

sudo cp ~/helium_miner_scripts/service_files/lora-gw-restart.service /etc/systemd/system/lora-gw-restart.service
sudo cp ~/helium_miner_scripts/service_files/lora-pkt-fwd.service /etc/systemd/system/lora-pkt-fwd.service

sudo systemctl enable lora-gw-restart.service
sudo systemctl enable lora-pkt-fwd.service
sudo systemctl start lora-gw-restart.service
sudo systemctl start lora-pkt-fwd.service

cd ~
git clone https://github.com/helium/gateway-config.git
cd gateway-config
make && make release

cp -R _build/prod/rel/gateway_config /opt/gateway_config

cp -R _build/prod/rel/gateway_config/config/com.helium.Config.conf /etc/dbus-1/system.d/

sudo service dbus restart

cd _build/prod/rel/gateway_config && sudo bin/gateway_config start

sudo touch ~/crondump
sudo chmod 777 ~/crondump
sudo crontab -l > ~/crondump
echo "@reboot cd _build/prod/rel/gateway_config && sudo bin/gateway_config start" >> ~/crondump
echo "@reboot sudo mount /dev/mmcblk0p1 /boot" >> ~/crondump
sudo crontab -u pi ~/crondump

# I think one of these was causing issues booting after applying.
sudo raspi-config nonint do_spi 1
sudo raspi-config nonint do_i2c 1
sudo raspi-config nonint do_serial 1
sudo raspi-config nonint do_wifi_country US
sudo raspi-config nonint do_ssh 1

locale=en_US.UTF-8
layout=us
sudo raspi-config nonint do_change_locale $locale
sudo raspi-config nonint do_configure_keyboard $layout

#add swap
sudo dphys-swapfile swapoff
sudo sed -i -e 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=1024/g' /etc/dphys-swapfile

echo "rebooting the pi in 10 seconds, CTRL + C to stop"
sleep 10
sudo reboot
