#!/bin/bash
cat >> /etc/sysctl.conf << 'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p
echo "BBR enabled"
