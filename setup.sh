#!/bin/bash

read -p "Enter left or right: " SIDE

if [ "$SIDE" = "left" ]; then
    IP="192.168.100.1/24"
elif [ "$SIDE" = "right" ]; then
    IP="192.168.100.2/24"
else
    echo "Invalid choice. Enter left or right."
    exit 1
fi

echo "$SIDE" | sudo tee /etc/hostname > /dev/null

sudo tee /etc/hosts > /dev/null <<EOF
127.0.0.1 localhost
127.0.1.1 $SIDE
192.168.100.1 left
192.168.100.2 right
EOF

sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null <<EOF
network: {config: disabled}
EOF

sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  ethernets:
    ens33:
      dhcp4: true
    ens34:
      dhcp4: false
      addresses:
        - $IP
  version: 2
EOF

sudo reboot

