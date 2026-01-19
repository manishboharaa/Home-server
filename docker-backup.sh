#!/bin/bash
# Backup Script for /home/docker

BACKUP_PATH="/home/backups"
SOURCE_DIR="/home/docker"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
FILENAME="docker_backup_$TIMESTAMP.zip"

mkdir -p $BACKUP_PATH

echo "Stopping all containers to ensure data integrity..."
docker stop $(docker ps -q)

echo "Compressing $SOURCE_DIR..."
# Install zip if not present
apt install -y zip
zip -r $BACKUP_PATH/$FILENAME $SOURCE_DIR

echo "Restarting containers..."
# Loop through and restart based on compose files
for d in $SOURCE_DIR/*/; do
    if [ -f "$d/docker-compose.yml" ]; then
        cd "$d" && docker compose up -d
    fi
done

echo "Backup completed: $BACKUP_PATH/$FILENAME"