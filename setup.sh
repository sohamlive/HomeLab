#!/bin/bash
# ============================================================
# Raspberry Pi Home Lab — Bootstrap Setup Script
# Run this once on a fresh Pi OS install to get everything up.
# Usage: chmod +x setup.sh && sudo ./setup.sh
# ============================================================

set -e  # Exit on any error

STATIC_IP="192.168.1.2"
ROUTER_IP="192.168.1.1"
FALLBACK_DNS="1.1.1.1"
# Pi uses its own Pi-hole (127.0.0.1) for DNS, with Cloudflare as fallback.
# Do NOT set this to 192.168.1.1 — that bypasses Pi-hole entirely.

echo "============================================"
echo "  Pi Home Lab — Setup Starting"
echo "============================================"

# ------------------------------------------------------------
# STEP 1: Set static local IP (Pi OS Bookworm+ uses NetworkManager)
# dhcpcd.conf is no longer used on Pi OS 12 (Bookworm) and later.
# The correct tool is nmcli.
# ------------------------------------------------------------
echo ""
echo "[1/6] Setting static local IP to $STATIC_IP via NetworkManager..."

# Detect the active ethernet interface and its connection name
INTERFACE=$(ip route | grep default | awk '{print $5}')
echo "      Detected network interface: $INTERFACE"

# Get the NetworkManager connection name for this interface
# Usually "Wired connection 1" on a fresh Pi OS install
CONN_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ":$INTERFACE" | cut -d: -f1)

if [ -z "$CONN_NAME" ]; then
  echo "      ERROR: Could not find an active NetworkManager connection for $INTERFACE"
  echo "      Run 'nmcli device status' to check your connection name and set it manually."
  exit 1
fi

echo "      Found connection: \"$CONN_NAME\""

# Apply static IP settings
nmcli con mod "$CONN_NAME" ipv4.addresses "$STATIC_IP/24"
nmcli con mod "$CONN_NAME" ipv4.gateway "$ROUTER_IP"
nmcli con mod "$CONN_NAME" ipv4.dns "127.0.0.1 $FALLBACK_DNS"
nmcli con mod "$CONN_NAME" ipv4.method manual

echo "      Static IP configured. Restarting connection..."
echo "      NOTE: If you are connected via SSH, your session will drop here."
echo "      Reconnect to $STATIC_IP after a few seconds."

# Bring connection down and up to apply — SSH will drop here if remote
nmcli con down "$CONN_NAME" && nmcli con up "$CONN_NAME" || true

echo "      Network restarted with static IP $STATIC_IP"

# ------------------------------------------------------------
# STEP 2: Update system
# ------------------------------------------------------------
echo ""
echo "[2/7] Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
echo "      Done."

# ------------------------------------------------------------
# STEP 3: Install log2ram — reduces SD card wear
# Moves /var/log to RAM, syncs to disk once daily.
# Must be installed BEFORE Docker so it's active when
# containers start writing logs.
# ------------------------------------------------------------
echo ""
echo "[3/7] Installing log2ram..."

if systemctl is-active --quiet log2ram; then
  echo "      log2ram already running. Skipping."
else
  # Install rsync (required by log2ram)
  apt-get install -y rsync -qq

  # Add azlux repo and install log2ram
  printf 'deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main' \
    | tee /etc/apt/sources.list.d/azlux.list
  wget -qO /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
  apt-get update -qq
  apt-get install -y log2ram

  # Configure log2ram:
  # - SIZE 128M: enough headroom for system + Docker + Pi-hole logs in RAM
  #   Default 40M is too small when running multiple Docker services.
  # - MAIL false: don't send email alerts on sync failure (no mail server here)
  # - JOURNALD_AWARE true (default): log2ram rotates journald logs before sync
  sed -i 's/^SIZE=.*/SIZE=128M/' /etc/log2ram.conf
  sed -i 's/^MAIL=.*/MAIL=false/' /etc/log2ram.conf

  # Cap journald to half of log2ram SIZE so it never overflows the RAM disk.
  # log2ram docs recommend SystemMaxUse = half of SIZE.
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/log2ram.conf <<'JEOF'
[Journal]
SystemMaxUse=64M
JEOF

  echo "      log2ram installed. SIZE=128M, journald capped at 64M."
  echo "      NOTE: log2ram requires a reboot to activate."
  echo "      The script will continue — reboot at the end."
fi

# ------------------------------------------------------------
# STEP 4: Install Docker (skip if already installed)
# ------------------------------------------------------------
echo ""
echo "[4/8] Checking Docker installation..."

if ! command -v docker &> /dev/null; then
  echo "      Docker not found. Installing..."
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker $SUDO_USER
  echo "      Docker installed. Note: log out and back in for group changes to take effect."
else
  echo "      Docker already installed. Skipping."
fi

# Install docker compose plugin if not present
if ! docker compose version &> /dev/null; then
  echo "      Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
else
  echo "      Docker Compose already available."
fi

# ------------------------------------------------------------
# STEP 5: Create config directories and seed config files
# ------------------------------------------------------------
echo ""
echo "[5/8] Creating config directories and seeding config files..."

mkdir -p ./nginx/data
mkdir -p ./nginx/letsencrypt
mkdir -p ./homepage/config/images
mkdir -p ./filebrowser

# ---- File Browser: pre-create required files ----
# Filebrowser WILL NOT START without these files existing on disk first.
if [ ! -f ./filebrowser/filebrowser.db ]; then
  touch ./filebrowser/filebrowser.db
  echo "      Created filebrowser/filebrowser.db"
fi

if [ ! -f ./filebrowser/settings.json ]; then
cat > ./filebrowser/settings.json <<'FBEOF'
{
  "port": 80,
  "baseURL": "",
  "address": "",
  "log": "stdout",
  "database": "/database/filebrowser.db",
  "root": "/srv"
}
FBEOF
echo "      Created filebrowser/settings.json"
fi

# ---- Homepage: services.yaml ----
if [ ! -f ./homepage/config/services.yaml ]; then
cat > ./homepage/config/services.yaml <<'SVCEOF'
- Network:
    - ISP Router:
        href: http://192.168.1.1
        description: Main ISP Gateway
        icon: router.png
        ping: 192.168.1.1
    - TP-Link Router:
        href: http://192.168.1.3
        description: Personal Router (AP Mode)
        icon: tp-link.png
        ping: 192.168.1.3
    - Pi-hole:
        href: http://pihole.lab/admin
        description: DNS & Ad Blocking
        icon: pi-hole.png
        widget:
          type: pihole
          url: http://192.168.1.2:8053
          version: 6
          key: YOUR_PIHOLE_PASSWORD_HERE

- Home Lab:
    - Folioman:
        href: http://portfolio.lab
        description: Mutual Fund Portfolio Tracker
        icon: mdi-finance
    - Portainer:
        href: http://portainer.lab
        description: Docker Management
        icon: portainer.png
    - Nginx Proxy Manager:
        href: http://proxy.lab
        description: Reverse Proxy & Local Hosts
        icon: nginx-proxy-manager.png
    - Uptime Kuma:
        href: http://uptime.lab
        description: Uptime Monitoring
        icon: uptime-kuma.png
    - Dozzle:
        href: http://logs.lab
        description: Container Log Viewer
        icon: docker.png
    - Netdata:
        href: http://stats.lab
        description: System Stats & Performance
        icon: netdata.png
    - File Browser:
        href: http://files.lab
        description: Web File Manager
        icon: filebrowser.png
SVCEOF
echo "      Created homepage/config/services.yaml"
fi

# ---- Homepage: widgets.yaml ----
if [ ! -f ./homepage/config/widgets.yaml ]; then
cat > ./homepage/config/widgets.yaml <<'WGEOF'
- greeting:
    text_size: xl
    text: "Home Lab"

- datetime:
    text_size: l
    format:
      dateStyle: long
      timeStyle: short
      hourCycle: h23

- openmeteo:
    label: Jamshedpur
    latitude: 22.804083
    longitude: 86.169111
    timezone: Asia/Kolkata
    units: metric
    cache: 5
    format:
      maximumFractionDigits: 1

- resources:
    label: CPU
    cpu: true
    cputemp: true
    units: celsius

- resources:
    label: Memory
    memory: true

- resources:
    label: Storage
    disk: /

- search:
    provider: google
    target: _blank
WGEOF
echo "      Created homepage/config/widgets.yaml"
fi

# ---- Homepage: settings.yaml ----
if [ ! -f ./homepage/config/settings.yaml ]; then
cat > ./homepage/config/settings.yaml <<'STEOF'
title: Home Lab
favicon: https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/pi-hole.png

theme: dark
color: slate

background:
  image: /images/background.jpg
  blur: sm
  saturate: 100
  brightness: 60
  opacity: 80

layout:
  Network:
    style: row
    columns: 3
    header: true
    icon: mdi-network
  Home Lab:
    style: row
    columns: 3
    header: true
    icon: mdi-server

useEqualHeights: true
cardBlur: sm

language: en
STEOF
echo "      Created homepage/config/settings.yaml"
fi

# ---- Fix ownership so your user can edit configs without sudo ----
chown -R $SUDO_USER:$SUDO_USER ./homepage/
chown -R $SUDO_USER:$SUDO_USER ./nginx/
chown -R $SUDO_USER:$SUDO_USER ./filebrowser/
echo "      Ownership set to $SUDO_USER for all config directories"
echo ""
echo "      NOTE: Add your background image at:"
echo "        ~/homelab/homepage/config/images/background.jpg"
echo "      Then update services.yaml: replace YOUR_PIHOLE_PASSWORD_HERE with your Pi-hole password."

# ------------------------------------------------------------
# STEP 6: Install CUPS print server + Epson driver
# Enables the Epson L3110 (USB) to be shared over the network.
# Avahi handles AirPrint (iPhone/Mac), Samba handles Windows.
# ------------------------------------------------------------
echo ""
echo "[6/8] Installing CUPS print server and Epson driver..."

apt-get install -y cups printer-driver-escpr avahi-daemon avahi-utils samba -qq

# Add user to lpadmin so they can manage printers without sudo
usermod -aG lpadmin $SUDO_USER

# Start CUPS first — cupsctl will fail with "Host is down" if CUPS isn't running
systemctl start cups
sleep 3

# Enable web interface
cupsctl WebInterface=yes || true

# Allow network access and sharing
cupsctl --share-printers || true
cupsctl BrowseLocalProtocols=dnssd || true

# Also set these directly in cupsd.conf as fallback
# in case cupsctl fails due to timing/state issues
if ! grep -q "WebInterface Yes" $CUPSD_CONF; then
  echo "WebInterface Yes" >> $CUPSD_CONF
fi
if ! grep -q "Browsing On" $CUPSD_CONF; then
  echo "Browsing On" >> $CUPSD_CONF
fi
if ! grep -q "BrowseLocalProtocols" $CUPSD_CONF; then
  echo "BrowseLocalProtocols dnssd" >> $CUPSD_CONF
fi

# Change Listen localhost:631 to Port 631
sed -i 's/^Listen localhost:631/Port 631/' $CUPSD_CONF

# Add ServerAlias and encryption settings after Port 631 if not present
if ! grep -q "ServerAlias \*" $CUPSD_CONF; then
  sed -i '/^Port 631/a ServerAlias *\nBrowsing On\nBrowseLocalProtocols dnssd\nDefaultEncryption IfRequested' $CUPSD_CONF
fi

# Allow @LOCAL and Tailscale subnet (100.x.x.x) in all Location blocks
sed -i '/<Location \/>/,/<\/Location>/ s/Order allow,deny/Order allow,deny\n  Allow @LOCAL\n  Allow 100.0.0.0\/8/' $CUPSD_CONF 2>/dev/null || true
sed -i '/<Location \/admin>/,/<\/Location>/ s/Order allow,deny/Order allow,deny\n  Allow @LOCAL\n  Allow 100.0.0.0\/8/' $CUPSD_CONF 2>/dev/null || true
sed -i '/<Location \/admin\/conf>/,/<\/Location>/ s/Order allow,deny/Order allow,deny\n  Allow @LOCAL\n  Allow 100.0.0.0\/8/' $CUPSD_CONF 2>/dev/null || true

# Create Samba spool directory
mkdir -p /var/spool/samba
chmod 1777 /var/spool/samba

# Update smb.conf — fix printers block path and guest access
sed -i '/^\[printers\]/,/^\[/ {
  s|path = /var/tmp|path = /var/spool/samba|
  s|guest ok = no|guest ok = yes|
}' /etc/samba/smb.conf

# Create Avahi AirPrint service file for Epson L3110
# NOTE: Update the rp= and adminurl= lines if you name your printer differently in CUPS
mkdir -p /etc/avahi/services
cat > /etc/avahi/services/Epson-L3110.service <<'AVEOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Epson L3110 @ %h</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/Epson-L3110</txt-record>
    <txt-record>ty=Epson L3110</txt-record>
    <txt-record>adminurl=http://192.168.1.2:631/printers/Epson-L3110</txt-record>
    <txt-record>note=Epson L3110 Print Server</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>Transparent=T</txt-record>
    <txt-record>URF=none</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,image/urf</txt-record>
    <txt-record>Color=T</txt-record>
    <txt-record>Copies=T</txt-record>
    <txt-record>product=(ESP)</txt-record>
  </service>
</service-group>
AVEOF

# Enable and restart all print services
systemctl enable cups avahi-daemon smbd
systemctl restart cups avahi-daemon smbd

echo "      CUPS, Avahi, and Samba installed and configured."
echo "      NOTE: You still need to add the printer manually via CUPS web UI."
echo "        Visit http://192.168.1.2:631 after setup to add the Epson L3110."
echo "        (Make sure the printer is plugged into the Pi's USB port first)"

# ------------------------------------------------------------
# STEP 7: Pull all images and start services
# ------------------------------------------------------------
echo ""
echo "[7/8] Pulling Docker images and starting services..."
docker compose pull
docker compose up -d
echo "      All services started."

# ------------------------------------------------------------
# STEP 8: Clone, configure and start Folioman (separate stack)
# Folioman is a Mutual Fund Portfolio Tracker. It ships its own
# docker-compose.yml with app/scheduler/db services and is built
# from source, so it runs as an independent stack alongside the
# main homelab stack — not merged into docker-compose.yml above.
# Local URL: http://portfolio.lab (proxied to port 8000)
# ------------------------------------------------------------
echo ""
echo "[8/9] Setting up Folioman (Mutual Fund Portfolio Tracker)..."

FOLIOMAN_DIR="/home/$SUDO_USER/folioman"

if [ -d "$FOLIOMAN_DIR" ]; then
  echo "      Folioman directory already exists. Skipping clone."
else
  echo "      Cloning Folioman repo..."
  sudo -u $SUDO_USER git clone https://github.com/codereverser/folioman "$FOLIOMAN_DIR"
fi

cd "$FOLIOMAN_DIR"

if [ ! -f server/.env ]; then
  echo "      Generating server/.env with fresh secrets..."
  cp server/.env.example server/.env

  # Generate required secrets
  SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(64))")

  # cryptography may not be installed yet — install if missing
  pip3 show cryptography > /dev/null 2>&1 || pip3 install cryptography --break-system-packages -q
  FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

  # Random strong DB password
  DB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")

  sed -i "s|^FOLIOMAN_SECRET_KEY=.*|FOLIOMAN_SECRET_KEY=${SECRET_KEY}|" server/.env
  sed -i "s|^FOLIOMAN_FERNET_KEY=.*|FOLIOMAN_FERNET_KEY=${FERNET_KEY}|" server/.env
  sed -i "s|^FOLIOMAN_DB_PASSWORD=.*|FOLIOMAN_DB_PASSWORD=${DB_PASSWORD}|" server/.env
  sed -i "s|^FOLIOMAN_ALLOWED_HOSTS=.*|FOLIOMAN_ALLOWED_HOSTS=portfolio.lab,${STATIC_IP},homepi.darter-economy.ts.net|" server/.env

  echo ""
  echo "      *** IMPORTANT — BACK THIS UP ***"
  echo "      FOLIOMAN_FERNET_KEY=${FERNET_KEY}"
  echo "      Without this key, encrypted PANs in the database are UNRECOVERABLE."
  echo "      It has been saved to server/.env — back that file up separately too."
  echo ""
else
  echo "      server/.env already exists. Skipping secret generation."
fi

chown -R $SUDO_USER:$SUDO_USER "$FOLIOMAN_DIR"

echo "      Building and starting Folioman stack (this takes a few minutes on first run)..."
docker compose -f server/docker-compose.yml up -d --build

echo "      Folioman started. Checking health..."
sleep 10
curl -s localhost:8000/api/health || echo "      (Health check not ready yet — give it another minute)"

echo ""
echo "      NOTE: First-run setup token is needed to create your admin account."
echo "      Get it with:"
echo "        cd $FOLIOMAN_DIR && docker compose -f server/docker-compose.yml logs app | grep -A4 'first-run setup'"

cd "$OLDPWD"

# ------------------------------------------------------------
# STEP 9: Enable services on boot
# ------------------------------------------------------------
echo ""
echo "[9/9] Ensuring all services start on boot..."
systemctl enable docker
echo "      Done."

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Services running at:"
echo "    http://$STATIC_IP:81     → Nginx Proxy Manager admin"
echo "    http://$STATIC_IP:8053   → Pi-hole"
echo "    http://$STATIC_IP:9000   → Portainer"
echo "    http://$STATIC_IP:3000   → Homepage"
echo "    http://$STATIC_IP:3001   → Uptime Kuma"
echo "    http://$STATIC_IP:8080   → Dozzle"
echo "    http://$STATIC_IP:19999  → Netdata"
echo "    http://$STATIC_IP:8085   → File Browser (default login: admin / admin)"
echo "    http://$STATIC_IP:8000   → Folioman"
echo "    http://$STATIC_IP:631    → CUPS Print Server"
echo ""
echo "  Manual steps after reboot:"
echo "    1. http://$STATIC_IP:81       → Configure *.lab reverse proxy routes in Nginx"
echo "    2. ISP router (192.168.1.1)   → DHCP settings → set Primary DNS to 192.168.1.2"
echo "    3. Tailscale                  → curl -fsSL https://tailscale.com/install.sh | sh"
echo "                                    sudo tailscale up"
echo "    4. Tailscale dashboard        → DNS → Enable HTTPS Certificates"
echo "    5. Tailscale dashboard        → DNS → Add nameserver → 100.x.x.x → Restrict to domain: lab"
echo "    6. http://$STATIC_IP:631      → Add Epson L3110 printer (plug USB in first)"
echo "    7. Run tailscale-serve.sh     → enables web UI access from anywhere via Tailscale"
echo "    8. Change File Browser password at http://$STATIC_IP:8085"
echo "    9. Update services.yaml       → replace YOUR_PIHOLE_PASSWORD_HERE"
echo "   10. Copy background image      → scp image.jpg soham@$STATIC_IP:~/homelab/homepage/config/images/background.jpg"
echo "   11. Folioman first login       → get setup token (see message above), create admin account at http://portfolio.lab"
echo "   12. Folioman backup            → back up server/.env (FOLIOMAN_FERNET_KEY) somewhere safe, separately from the Pi"
echo ""
echo "  Pi-hole password: changeme  ← change FTLCONF_webserver_api_password in docker-compose.yml first!"
echo ""
echo "  *** REBOOT REQUIRED ***"
echo "  log2ram needs a reboot to activate."
echo "  Run: sudo reboot"
echo "  After reboot: sudo systemctl status log2ram"
echo ""