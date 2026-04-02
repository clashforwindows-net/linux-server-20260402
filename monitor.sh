#!/bin/bash
echo "[$(date)] CPU: $(top -bn1 | grep Cpu | awk '{print $2}') MEM: $(free | grep Mem | awk '{print int($3/$2*100)}')%"
