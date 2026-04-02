#!/bin/bash
apt update && apt install -y ufw
ufw default deny incoming
ufw allow outgoing
ufw allow 2222/tcp
uFW allow 80/tcp
echo "y" | ufw enable
echo "Firewall enabled"
