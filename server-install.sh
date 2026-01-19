#!/bin/bash

# ==============================================================================
# UBUNTU SERVER MASTER INSTALLER (2026 EDITION)
# ==============================================================================
# Description: Automated setup for Docker, Cockpit, and self-hosted suite.
# Targets: Portainer, Glance, Paperless, Immich, Code-Server, VERT, 
#          Uptime Kuma, FileBrowser (Root), and myDrive.
# ==============================================================================

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo ./master_setup.sh)"
  exit 1
fi

# --- Variables & Environment ---
BASE_DIR="/home/docker"
SERVER_IP=$(hostname -I | awk '{print $1}')
mkdir -p "$BASE_DIR"

# --- Helper: Directory Creation ---
setup_folders() {
    echo "Creating folders for $1..."
    mkdir -p "$BASE_DIR/$1/config" "$BASE_DIR/$1/data"
}

# --- Core: System Maintenance ---
install_prerequisites() {
    echo "Updating system and installing base tools..."
    apt update && apt upgrade -y
    apt install -y ca-certificates curl gnupg lsb-release ufw software-properties-common openssl
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker Engine and Compose..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
}

fix_lid_sleep() {
    echo "Applying Lid Close Fix (Computer will not sleep)..."
    sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
    sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
    systemctl restart systemd-logind
}

# ==============================================================================
# APPLICATION INSTALLERS
# ==============================================================================

install_cockpit() {
    echo "Installing Cockpit (Native Host)..."
    apt install -y cockpit
    systemctl enable --now cockpit.socket
    ufw allow 9090/tcp
}

install_portainer() {
    setup_folders "portainer"
    cat <<EOF > "$BASE_DIR/portainer/docker-compose.yml"
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
EOF
    cd "$BASE_DIR/portainer" && docker compose up -d
    ufw allow 9443/tcp
}

iinstall_glance() {
    setup_folders "glance"
    
    echo "Generating Glance Dashboard with System Health & Icons..."
    cat <<EOF > "$BASE_DIR/glance/config/glance.yml"
theme: dark
pages:
  - name: Home Server
    columns:
      - size: small
        widgets:
          - type: monitor
            title: System Health
            cache: 30s
            items:
              - label: CPU Load
                type: cpu
              - label: RAM Usage
                type: memory
              - label: Root Disk
                type: filesystem
                path: /
          - type: calendar
          - type: weather
            location: London # Change to your city
            unit: celsius

      - size: full
        widgets:
          - type: bookmarks
            groups:
              - name: Management
                links:
                  - title: Portainer
                    url: https://$SERVER_IP:9443
                    icon: si:docker
                  - title: Cockpit
                    url: https://$SERVER_IP:9090
                    icon: si:linux
                  - title: FileBrowser
                    url: http://$SERVER_IP:8082
                    icon: si:files
              - name: Applications
                links:
                  - title: Immich
                    url: http://$SERVER_IP:2283
                    icon: si:googlephotos
                  - title: Paperless
                    url: http://$SERVER_IP:8010
                    icon: si:read-the-docs
                  - title: Code Server
                    url: http://$SERVER_IP:8443
                    icon: si:visualstudiocode
                  - title: Uptime Kuma
                    url: http://$SERVER_IP:3001
                    icon: si:statuspage
EOF

    cat <<EOF > "$BASE_DIR/glance/docker-compose.yml"
services:
  glance:
    image: glanceapp/glance:latest
    container_name: glance
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./config/glance.yml:/app/config/glance.yml
EOF

    cd "$BASE_DIR/glance" && docker compose up -d
    ufw allow 8080/tcp
}

install_paperless() {
    setup_folders "paperless"
    cat <<EOF > "$BASE_DIR/paperless/docker-compose.yml"
services:
  broker:
    image: redis:7
    restart: unless-stopped
  db:
    image: postgres:15
    restart: unless-stopped
    environment:
      - POSTGRES_DB=paperless
      - POSTGRES_USER=paperless
      - POSTGRES_PASSWORD=paperless
    volumes:
      - ./data/db:/var/lib/postgresql/data
  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    depends_on: [db, broker]
    ports:
      - "8010:8000"
    volumes:
      - ./data:/usr/src/paperless/data
      - ./config:/usr/src/paperless/consume
    environment:
      - PAPERLESS_REDIS=redis://broker:6379
      - PAPERLESS_DBHOST=db
      - PAPERLESS_SECRET_KEY=$(openssl rand -hex 32)
EOF
    cd "$BASE_DIR/paperless" && docker compose up -d
    ufw allow 8010/tcp
}

install_immich() {
    setup_folders "immich"
    cat <<EOF > "$BASE_DIR/immich/docker-compose.yml"
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:latest
    container_name: immich_server
    ports:
      - "2283:2283"
    volumes:
      - ./data:/usr/src/app/upload
    restart: always
EOF
    cd "$BASE_DIR/immich" && docker compose up -d
    ufw allow 2283/tcp
}

install_code_server() {
    setup_folders "code-server"
    cat <<EOF > "$BASE_DIR/code-server/docker-compose.yml"
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config:/config
      - ./data:/data
    ports:
      - "8443:8443"
    restart: unless-stopped
EOF
    cd "$BASE_DIR/code-server" && docker compose up -d
    ufw allow 8443/tcp
}

install_vert() {
    setup_folders "vert"
    cat <<EOF > "$BASE_DIR/vert/docker-compose.yml"
services:
  vert:
    image: ghcr.io/vert-sh/vert:main
    container_name: vert
    ports:
      - "3000:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config:/app/config
    restart: always
EOF
    cd "$BASE_DIR/vert" && docker compose up -d
    ufw allow 3000/tcp
}

install_uptime_kuma() {
    setup_folders "uptime-kuma"
    cat <<EOF > "$BASE_DIR/uptime-kuma/docker-compose.yml"
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
    restart: always
EOF
    cd "$BASE_DIR/uptime-kuma" && docker compose up -d
    ufw allow 3001/tcp
}

install_filebrowser() {
    setup_folders "filebrowser"
    cat <<EOF > "$BASE_DIR/filebrowser/docker-compose.yml"
services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    user: 0:0
    ports:
      - "8082:80"
    volumes:
      - /:/srv
      - ./data/filebrowser.db:/database.db
      - ./config/settings.json:/config/settings.json
    restart: always
EOF
    touch "$BASE_DIR/filebrowser/data/filebrowser.db"
    cd "$BASE_DIR/filebrowser" && docker compose up -d
    ufw allow 8082/tcp
}

install_mydrive() {
    setup_folders "mydrive"
    cat <<EOF > "$BASE_DIR/mydrive/docker-compose.yml"
services:
  mydrive:
    image: subnub/mydrive:latest
    container_name: mydrive
    ports:
      - "3002:3002"
    environment:
      - MONGO_URI=mongodb://mongo:27017/mydrive
      - JWT_SECRET=$(openssl rand -hex 16)
    depends_on:
      - mongo
    restart: always
  mongo:
    image: mongo:latest
    volumes:
      - ./data/db:/data/db
EOF
    cd "$BASE_DIR/mydrive" && docker compose up -d
    ufw allow 3002/tcp
}

# ==============================================================================
# MENU SYSTEM
# ==============================================================================

clear
echo "====================================================="
echo "   MASTER SERVER INSTALLER - IP: $SERVER_IP "
echo "====================================================="
echo "1)  FULL SUITE (Install Everything + Fixes)"
echo "2)  Portainer"
echo "3)  Glance Dashboard (with Health Widget)"
echo "4)  Paperless-ngx"
echo "5)  Immich Server"
echo "6)  Code-Server (VS Code)"
echo "7)  Cockpit (Native)"
echo "8)  VERT (Server Manager)"
echo "9)  Uptime Kuma"
echo "10) FileBrowser (ROOT ACCESS)"
echo "11) myDrive"
echo "-----------------------------------------------------"
echo "L)  Apply Laptop Lid Sleep Fix"
echo "q)  Quit"
echo "====================================================="
read -p "Select an option: " choice

# Init Core Requirements
install_prerequisites
install_docker
ufw allow 22/tcp
echo "y" | ufw enable

case $choice in
    1) fix_lid_sleep; install_cockpit; install_portainer; install_glance; install_paperless; install_immich; install_code_server; install_vert; install_uptime_kuma; install_filebrowser; install_mydrive ;;
    2) install_portainer ;;
    3) install_glance ;;
    4) install_paperless ;;
    5) install_immich ;;
    6) install_code_server ;;
    7) install_cockpit ;;
    8) install_vert ;;
    9) install_uptime_kuma ;;
    10) install_filebrowser ;;
    11) install_mydrive ;;
    L) fix_lid_sleep ;;
    q) exit 0 ;;
esac

echo -e "\nSetup Finished! Access your Dashboard at http://$SERVER_IP:8080"