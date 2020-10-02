#!/bin/bash

# Hello!
# Donations are always appreciated!
# bitcoin: bc1qzhhkseykxwsrqfne6f5r6w49lh4htfv9sh6g6w
# ethereum: 0x07D64BBd2875504992f28FB7400e538a334efDDB
# tron: TXiVtDMDCCX6f6xXMsqyzw6QMFGmGGyrnW
# IXIAN: 59VSYAMafig4toPuKqUPVnc6qevfg4incBT4yPcQoSXqnjzcThYMAGp4kDg3RaWsb

# Filename: install-ubuntu-no-docker-with-ble.sh
#
# Pi Requirements: 2B, 3B, 3A+, 3B+, 4B (2GB, 4GB, 8GB), Zero, Zero W, Zero WH
# Assumed build for this script: Raspberry Pi 2B
# + RAK2287 Pi Hat
# + RAK2287 LPWAN SX1302
# + Geekworm Raspberry Pi X710 Power Management Board
# + Bluetooth 4.0 Adapter
# + WiFi module

# Check for whiptail
USER=sysadmin
WT_HEIGHT=10
WT_WIDTH=60

clear
echo "Checking for whiptail..."
if [ $(sudo dpkg-query -W -f='${Status}' whiptail 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
  sudo whiptail --msgbox "Whiptail present and ready..." $WT_HEIGHT $WT_WIDTH
else
  sudo apt-get install whiptail -fy
  sudo whiptail --msgbox "Whiptail installed and ready..." $WT_HEIGHT $WT_WIDTH
fi

# Check if root
echo "Checking for sudo/root..."
echo
if [ "$(whoami)" != "root" ]; then
  whiptail --msgbox "Sorry you are not root. You must type: sudo sh install.sh" $WT_HEIGHT $WT_WIDTH
  exit
fi

#lets make sure everything is updated and upgraded before continuing
sudo apt update -y
sudo apt upgrade -y

# Check if raspi-config is installed if not lets get it installed
if [ $(dpkg-query -W -f='${Status}' raspi-config 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
  whiptail --msgbox "Raspi-config is already installed, try upgrading it within raspi-config..." 10 60
else
  wget https://archive.raspberrypi.org/debian/pool/main/r/raspi-config/raspi-config_20200902_all.deb -P /tmp
  apt-get install libnewt0.52 parted triggerhappy lua5.1 alsa-utils -y
  # Auto install dependancies on eg. ubuntu server on RPI
  apt-get install -fy
  dpkg -i /tmp/raspi-config_20200902_all.deb
  whiptail --msgbox "Raspi-config is now installed, run it by typing: sudo raspi-config" 10 60
fi
echo
echo "Install requirements..."
echo
#lets get some requirements installed (same requirements for raspberry pi with miner running on it)
sudo apt install curl jq git vim nano gcc build-essential -y

#lets get the miner ip address from the user
read -s -p "Enter Miner IP Address: " ipminer
echo
echo "The miner we are connecting to is: " $ipminer
echo
echo "Cloning packet_forwarder and lora_gateway..."
echo
cd ~
git clone https://github.com/Lora-net/packet_forwarder
git clone https://github.com/Lora-net/lora_gateway

cd packet_forwarder/lora_pkt_fwd

mv ~/packet_forwarder/lora_pkt_fwd/global_conf.json ~/packet_forwarder/lora_pkt_fwd/global_conf.json.1
curl -s -o ~/packet_forwarder/lora_pkt_fwd/global_conf.json 'https://helium-media.s3-us-west-2.amazonaws.com/global_conf.json'
#wget https://helium-media.s3-us-west-2.amazonaws.com/global_conf.json --backups

echo "Updating Gateway ID..."
# get gateway ID from its MAC address to generate an EUI-64 address
GWID_MIDFIX="FFFE"
GWID_BEGIN=$(ip link show eth0 | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3}')
GWID_END=$(ip link show eth0 | awk '/ether/ {print $2}' | awk -F\: '{print $4$5$6}')
GWID=$GWID_BEGIN$GWID_MIDFIX$GWID_END
sed -i 's/AA555A0000000000/'${GWID}'/g' /home/$USER/packet_forwarder/lora_pkt_fwd/global_conf.json
sed -i 's/\(^\s*"gateway_ID":\s*"\).\{16\}"\s*\(,\?\).*$/\1'${GWID_BEGIN}${GWID_MIDFIX}${GWID_END}'"\2/' /home/$USER/packet_forwarder/lora_pkt_fwd/local_conf.json

echo "Gateway ID updated sucessfully..."
echo "Setting SPI Speed..."
sed -i 's/#define SPI_SPEED       8000000/#define SPI_SPEED       2000000/' /home/$USER/lora_gateway/libloragw/src/loragw_spi.native.c

echo "Setting Miner IP Address in global_conf.json..."
sed -i 's/localhost/'${ipminer}'/g' ./global_conf.json
echo "Miner IP Address set to ${ipminer}"
echo
echo "Compiling..."
cd /home/pi/packet_forwarder/
./compile.sh
echo "Setting services..."
sudo cp ~/helium_miner_scripts/service_files/lora-gw-restart.service /etc/systemd/system/lora-gw-restart.service
sudo cp ~/helium_miner_scripts/service_files/lora-pkt-fwd.service /etc/systemd/system/lora-pkt-fwd.service

sudo systemctl enable lora-gw-restart.service
sudo systemctl enable lora-pkt-fwd.service
sudo systemctl start lora-gw-restart.service
sudo systemctl start lora-pkt-fwd.service
echo
echo "Setting up gateway-config..."
cd ~
git clone https://github.com/helium/gateway-config.git
cd gateway-config
make && make release

cp -R _build/prod/rel/gateway_config /opt/gateway_config

cp -R _build/prod/rel/gateway_config/config/com.helium.Config.conf /etc/dbus-1/system.d/

sudo service dbus restart
echo
echo "Running gateway config..."

cd _build/prod/rel/gateway_config && sudo bin/gateway_config start

echo "Setting gateway config to run on reboot..."
sudo touch ~/crondump
sudo chmod 777 ~/crondump
sudo crontab -l > ~/crondump
echo "@reboot cd _build/prod/rel/gateway_config && sudo bin/gateway_config start" >> ~/crondump
echo "@reboot sudo mount /dev/mmcblk0p1 /boot" >> ~/crondump
sudo crontab -u pi ~/crondump

echo
echo "Almost there..."
echo "Setting up raspberry pi specifics in config.txt..."
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

echo
echo "Reconfiguring swapfile..."
#add swap
sudo dphys-swapfile swapoff
sudo sed -i -e 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=1024/g' /etc/dphys-swapfile
echo
echo
echo "Were Done!!!"
echo
echo
echo "rebooting the pi in 10 seconds, CTRL + C to stop"
sleep 10
sudo reboot
