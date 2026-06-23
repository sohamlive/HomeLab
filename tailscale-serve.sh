#!/bin/bash
# ============================================================
# Raspberry Pi Home Lab — Tailscale Serve Setup
#
# What this does:
#   Maps each local service to a port on your Tailscale HTTPS
#   hostname so you can access them from any device logged into
#   your Tailscale account, from anywhere, without port numbers
#   in the URL.
#
# Requirements:
#   - Tailscale already installed and logged in (tailscale up)
#   - HTTPS certificates enabled in Tailscale admin dashboard:
#     login.tailscale.com → DNS → Enable HTTPS Certificates
#
# Usage:
#   chmod +x tailscale-serve.sh
#   sudo ./tailscale-serve.sh
#
# After running, your services will be at:
#   https://<your-pi-hostname>.<tailnet>.ts.net        → Homepage
#   https://<your-pi-hostname>.<tailnet>.ts.net:9000   → Portainer
#   https://<your-pi-hostname>.<tailnet>.ts.net:8054   → Pi-hole
#   https://<your-pi-hostname>.<tailnet>.ts.net:3001   → Uptime Kuma
#   https://<your-pi-hostname>.<tailnet>.ts.net:8080   → Dozzle
#   https://<your-pi-hostname>.<tailnet>.ts.net:19999  → Netdata
#   https://<your-pi-hostname>.<tailnet>.ts.net:8085   → File Browser
#   https://<your-pi-hostname>.<tailnet>.ts.net:81     → Nginx Proxy Manager
#   https://<your-pi-hostname>.<tailnet>.ts.net:8001   → Folioman
#
# All of these are private to your Tailscale network only.
# Only devices logged into your Tailscale account can reach them.
# ============================================================

set -e

echo ""
echo "============================================"
echo "  Tailscale Serve — Home Lab Setup"
echo "============================================"
echo ""

# Check Tailscale is running
if ! tailscale status > /dev/null 2>&1; then
  echo "ERROR: Tailscale is not running or not logged in."
  echo "Run: sudo tailscale up"
  exit 1
fi

# Get and display the Tailscale hostname
TS_HOSTNAME=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Self']['DNSName'].rstrip('.'))" 2>/dev/null || echo "unknown")
echo "  Pi Tailscale hostname: $TS_HOSTNAME"
echo ""

# ---- Homepage → served on default HTTPS port 443 ----
echo "[1/9] Homepage → https://$TS_HOSTNAME (port 443, default)"
tailscale serve --bg --https=443 3000
echo "      Done."

# ---- Portainer ----
echo "[2/9] Portainer → https://$TS_HOSTNAME:9000"
tailscale serve --bg --https=9000 9000
echo "      Done."

# ---- Pi-hole ----
echo "[3/9] Pi-hole → https://$TS_HOSTNAME:8053"
tailscale serve --bg --https=8054 8053
echo "      Done."

# ---- Uptime Kuma ----
echo "[4/9] Uptime Kuma → https://$TS_HOSTNAME:3001"
tailscale serve --bg --https=3001 3001
echo "      Done."

# ---- Dozzle ----
echo "[5/9] Dozzle → https://$TS_HOSTNAME:8080"
tailscale serve --bg --https=8080 8080
echo "      Done."

# ---- Netdata ----
echo "[6/9] Netdata → https://$TS_HOSTNAME:19999"
tailscale serve --bg --https=19999 19999
echo "      Done."

# ---- File Browser ----
echo "[7/9] File Browser → https://$TS_HOSTNAME:8085"
tailscale serve --bg --https=8085 8085
echo "      Done."

# ---- Nginx Proxy Manager ----
echo "[8/9] Nginx Proxy Manager → https://$TS_HOSTNAME:81"
tailscale serve --bg --https=81 81
echo "      Done."

# ---- Folioman Portfolio Manager ----
echo "[9/9] Folioman Portfolio Manager → https://$TS_HOSTNAME:8000"
tailscale serve --bg --https=8001 8000
echo "      Done."

# ---- Show final status ----
echo ""
echo "============================================"
echo "  All services registered. Current status:"
echo "============================================"
tailscale serve status

echo ""
echo "  Access your services from any device on your Tailscale"
echo "  network using the URLs shown above."
echo ""
echo "  To check status later:  tailscale serve status"
echo "  To remove a service:    sudo tailscale serve --https=<port> off"
echo "  To remove all:          sudo tailscale serve reset"
echo ""
