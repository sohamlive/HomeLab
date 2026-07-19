#!/bin/bash
# ============================================================
# Raspberry Pi Home Lab — Teardown Script
#
# What this removes:
#   - All running containers from the homelab stack
#   - All Docker images pulled for the stack
#   - All named Docker volumes (Pi-hole data, Portainer data, etc)
#   - All homelab config directories (nginx/, homepage/, filebrowser/)
#   - The Docker bridge network created by compose
#   - CUPS printer configuration (registered printers)
#   - Avahi AirPrint service file
#
# What this KEEPS:
#   - Docker and Docker Compose
#   - Tailscale
#   - Your static IP config (nmcli)
#   - CUPS, Samba, Avahi packages (just clears config)
#   - log2ram
#   - The docker-compose.yml, setup.sh, and other scripts
#   - The Pi OS and all system packages
#   - Folioman (~/folioman) — NEVER touched by default. It holds
#     real financial data (PANs encrypted with FOLIOMAN_FERNET_KEY).
#     This script asks separately, with a second explicit
#     confirmation, before touching it in any way.
#
# Usage:
#   chmod +x teardown.sh
#   sudo ./teardown.sh
#
# Run from the homelab directory (same place as docker-compose.yml)
# ============================================================

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No colour

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}  Pi Home Lab — Teardown Script${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo -e "${YELLOW}  This will remove all homelab containers, images,${NC}"
echo -e "${YELLOW}  volumes, and config directories.${NC}"
echo -e "${YELLOW}  Docker, Tailscale, and your OS are untouched.${NC}"
echo ""
read -p "  Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo ""
  echo "  Aborted. Nothing was changed."
  echo ""
  exit 0
fi

echo ""

# ------------------------------------------------------------
# STEP 1: Stop and remove all containers defined in compose
# ------------------------------------------------------------
echo "[1/5] Stopping and removing containers..."

if [ -f docker-compose.yml ]; then
  docker compose down --remove-orphans
  echo "      Done."
else
  echo "      docker-compose.yml not found in current directory."
  echo "      Skipping compose down — run this script from your homelab folder."
fi

# ------------------------------------------------------------
# STEP 2: Remove named volumes
# ------------------------------------------------------------
echo ""
echo "[2/5] Removing named Docker volumes..."

VOLUMES=(
  "homelab_pihole_data"
  "homelab_pihole_dnsmasq"
  "homelab_portainer_data"
  "homelab_uptime_kuma_data"
  "homelab_netdata_config"
  "homelab_netdata_lib"
  "homelab_netdata_cache"
  "homelab_filebrowser_data"
)

for VOL in "${VOLUMES[@]}"; do
  if docker volume inspect "$VOL" > /dev/null 2>&1; then
    docker volume rm "$VOL"
    echo "      Removed: $VOL"
  else
    echo "      Not found (skipping): $VOL"
  fi
done

# Also prune any dangling volumes not caught above
echo "      Pruning any remaining dangling volumes..."
docker volume prune -f
echo "      Done."

# ------------------------------------------------------------
# STEP 3: Remove Docker images
# ------------------------------------------------------------
echo ""
echo "[3/5] Removing Docker images..."

IMAGES=(
  "pihole/pihole"
  "portainer/portainer-ce"
  "jc21/nginx-proxy-manager"
  "ghcr.io/gethomepage/homepage"
  "louislam/uptime-kuma"
  "amir20/dozzle"
  "netdata/netdata"
  "filebrowser/filebrowser"
)

for IMG in "${IMAGES[@]}"; do
  if docker images --format "{{.Repository}}" | grep -q "^${IMG}$"; then
    docker rmi $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${IMG}:") 2>/dev/null || true
    echo "      Removed: $IMG"
  else
    echo "      Not found (skipping): $IMG"
  fi
done

# Prune any dangling image layers
echo "      Pruning dangling image layers..."
docker image prune -f
echo "      Done."

# ------------------------------------------------------------
# STEP 4: Remove the Docker network
# ------------------------------------------------------------
echo ""
echo "[4/5] Removing Docker network..."

if docker network inspect homelab_homelab > /dev/null 2>&1; then
  docker network rm homelab_homelab
  echo "      Removed: homelab_homelab"
else
  echo "      Network not found (skipping)."
fi

# ------------------------------------------------------------
# STEP 5: Remove config directories
# ------------------------------------------------------------
echo ""
echo "[5/6] Removing config directories..."

DIRS=(
  "./nginx"
  "./homepage/config"
  "./filebrowser"
)

for DIR in "${DIRS[@]}"; do
  if [ -d "$DIR" ]; then
    rm -rf "$DIR"
    echo "      Removed: $DIR"
  else
    echo "      Not found (skipping): $DIR"
  fi
done

# Remove homepage dir if now empty
if [ -d "./homepage" ] && [ -z "$(ls -A ./homepage)" ]; then
  rm -rf ./homepage
  echo "      Removed: ./homepage (was empty)"
fi

# ------------------------------------------------------------
# STEP 6: Remove CUPS printer config and Avahi AirPrint file
# ------------------------------------------------------------
echo ""
echo "[6/6] Removing CUPS printer config and Avahi AirPrint service..."

# Remove all registered printers from CUPS
for PRINTER in $(lpstat -p 2>/dev/null | awk '{print $2}'); do
  lpadmin -x "$PRINTER" 2>/dev/null && echo "      Removed CUPS printer: $PRINTER" || true
done

# Remove Avahi AirPrint service file
if [ -f /etc/avahi/services/Epson-L3110.service ]; then
  rm /etc/avahi/services/Epson-L3110.service
  systemctl restart avahi-daemon
  echo "      Removed Avahi AirPrint service file."
else
  echo "      Avahi service file not found (skipping)."
fi

echo "      Done."

# ------------------------------------------------------------
# STEP 7 (OPTIONAL): Folioman — explicit confirmation
# Folioman holds real financial data. It is NEVER touched unless
# you explicitly opt in here, with its own separate confirmation.
# ------------------------------------------------------------
echo ""
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "${YELLOW}  Folioman holds real financial data (mutual fund holdings,${NC}"
echo -e "${YELLOW}  PANs encrypted with FOLIOMAN_FERNET_KEY).${NC}"
echo -e "${YELLOW}  This is NOT removed by the steps above.${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo ""
read -p "  Do you also want to stop and remove Folioman? (yes/no): " FOLIOMAN_CONFIRM

if [ "$FOLIOMAN_CONFIRM" = "yes" ]; then
  echo ""
  echo -e "${RED}  This will delete the Folioman database (holdings, transactions,${NC}"
  echo -e "${RED}  valuations) UNLESS you have a backup. This cannot be undone.${NC}"
  read -p "  Type 'DELETE' (all caps) to confirm permanent removal: " FOLIOMAN_FINAL

  if [ "$FOLIOMAN_FINAL" = "DELETE" ]; then
    FOLIOMAN_DIR="/home/$SUDO_USER/folioman"
    if [ -d "$FOLIOMAN_DIR" ]; then
      cd "$FOLIOMAN_DIR"
      docker compose -f server/docker-compose.yml down -v
      docker volume rm server_folioman_pgdata 2>/dev/null || true
      cd "$OLDPWD"
      echo "      Folioman stack and database volume removed."
      echo "      Folioman code at $FOLIOMAN_DIR was NOT deleted — remove manually if desired:"
      echo "        rm -rf $FOLIOMAN_DIR"
    else
      echo "      Folioman directory not found (skipping)."
    fi
  else
    echo "      Confirmation text did not match. Folioman left untouched."
  fi
else
  echo "      Skipped. Folioman left running and untouched."
fi

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Teardown Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  What was removed:"
echo "    - All homelab containers"
echo "    - All homelab Docker volumes and data"
echo "    - All homelab Docker images"
echo "    - homelab Docker bridge network"
echo "    - nginx/, homepage/config/, filebrowser/ directories"
echo "    - CUPS registered printers"
echo "    - Avahi AirPrint service file"
echo ""
echo "  What was kept:"
echo "    - Docker and Docker Compose"
echo "    - Tailscale"
echo "    - Static IP configuration"
echo "    - CUPS, Samba, Avahi packages"
echo "    - log2ram"
echo "    - docker-compose.yml, setup.sh, teardown.sh, tailscale-serve.sh"
echo "    - Folioman — unless explicitly confirmed its removal above"
echo ""
echo "  To redeploy from scratch, run:"
echo "    sudo ./setup.sh"
echo ""
