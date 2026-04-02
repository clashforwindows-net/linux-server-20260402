#!/bin/bash
echo "VPS Bench"
echo "CPU: $(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d: -f2)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
dd if=/dev/zero of=test bs=64k count=256 oflag=dsync 2>&1 | grep copied
rm -f test
