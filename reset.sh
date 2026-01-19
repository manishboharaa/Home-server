#!/bin/bash

# Ensure root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

echo "--- Starting System Reset (keeping SSH & Lid settings) ---"

# 1. Stop and Wipe Docker
if command -v docker &> /dev/null; then
    echo "Stopping all containers and wiping Docker data..."
    docker stop $(docker ps -aq) 2>/dev/null
    docker system prune -a --volumes -f
    rm -rf /home/docker/*
fi

# 2. Clean Package Manager
apt autoremove -y
apt clean

# 3. Reset UFW (but keep SSH open)
ufw --force reset
ufw allow 22/tcp
echo "y" | ufw enable

# 4. Clear Logs
find /var/log -type f -exec cp /dev/null {} \;

echo "--- Reset Complete. User accounts and SSH remain intact. ---"