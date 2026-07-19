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
# PORT CONFLICT RULES:
#   Tailscale serve binds the EXTERNAL port number physically on
#   the host — the same way any process does. Since Tailscale
#   starts before Docker and CUPS on every reboot, any external
#   port that matches a service's own host port will conflict,
#   preventing that service from binding after reboot.
#
#   Rule: external (Tailscale) port must NEVER match the internal
#   (service) port for services that bind directly on the host.
#
#   Services that bind on the host (conflict-prone):
#     Pi-hole  → host port 8053  → TS external port 8054
#     CUPS     → host port 631   → TS external port 8632
#     Folioman → host port 8000  → TS external port 8001
#
#   Services inside Docker bridge only (safe to match):
#     Homepage, Portainer, Uptime Kuma, Dozzle, Netdata,
#     File Browser, Nginx Proxy Manager
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
# After running, the services will be at:
#   https://homepi.darter-economy.ts.net        → Homepage
#   https://homepi.darter-economy.ts.net:9000   → Portainer
#   https://homepi.darter-economy.ts.net:8054   → Pi-hole      (8053 reserved for host)
#   https://homepi.darter-economy.ts.net:3001   → Uptime Kuma
#   https://homepi.darter-economy.ts.net:8080   → Dozzle
#   https://homepi.darter-economy.ts.net:19999  → Netdata
#   https://homepi.darter-economy.ts.net:8085   → File Browser
#   https://homepi.darter-economy.ts.net:81     → Nginx Proxy Manager
#   https://homepi.darter-economy.ts.net:8632   → CUPS          (631 reserved for host)
#   https://homepi.darter-economy.ts.net:8001   → Folioman      (8000 reserved for host)
#
# For services which are port changed, can still be accessed
# in original port if using IP address - 
# eg - 192.168.1.2:631 - CUPS
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

# Clear any existing serve config first to avoid stale port bindings
echo "  Clearing existing Tailscale serve config..."
tailscale serve reset
echo ""

# ---- Homepage → default HTTPS port 443 ----
# External 443 ≠ internal 3000 — no conflict
echo "[1/10] Homepage → https://$TS_HOSTNAME"
tailscale serve --bg --https=443 3000
echo "       Done."

# ---- Portainer ----
# External 9000 = internal 9000 — safe, Portainer is inside Docker bridge
echo "[2/10] Portainer → https://$TS_HOSTNAME:9000"
tailscale serve --bg --https=9000 9000
echo "       Done."

# ---- Pi-hole ----
# External 8054 ≠ internal 8053 — avoids conflict with Pi-hole's host port binding
echo "[3/10] Pi-hole → https://$TS_HOSTNAME:8054"
tailscale serve --bg --https=8054 8053
echo "       Done."

# ---- Uptime Kuma ----
# External 3001 = internal 3001 — safe, inside Docker bridge
echo "[4/10] Uptime Kuma → https://$TS_HOSTNAME:3001"
tailscale serve --bg --https=3001 3001
echo "       Done."

# ---- Dozzle ----
# External 8080 = internal 8080 — safe, inside Docker bridge
echo "[5/10] Dozzle → https://$TS_HOSTNAME:8080"
tailscale serve --bg --https=8080 8080
echo "       Done."

# ---- Netdata ----
# External 19999 = internal 19999 — safe, inside Docker bridge
echo "[6/10] Netdata → https://$TS_HOSTNAME:19999"
tailscale serve --bg --https=19999 19999
echo "       Done."

# ---- File Browser ----
# External 8085 = internal 8085 — safe, inside Docker bridge
echo "[7/10] File Browser → https://$TS_HOSTNAME:8085"
tailscale serve --bg --https=8085 8085
echo "       Done."

# ---- Nginx Proxy Manager ----
# External 81 = internal 81 — safe, inside Docker bridge
echo "[8/10] Nginx Proxy Manager → https://$TS_HOSTNAME:81"
tailscale serve --bg --https=81 81
echo "       Done."

# ---- CUPS Print Server ----
# External 8632 ≠ internal 631 — avoids conflict with CUPS host port binding
echo "[9/10] CUPS → https://$TS_HOSTNAME:8632"
tailscale serve --bg --https=8632 631
echo "       Done."

# ---- Folioman ----
# External 8001 ≠ internal 8000 — avoids conflict with Folioman's host port binding
echo "[10/10] Folioman → https://$TS_HOSTNAME:8001"
tailscale serve --bg --https=8001 8000
echo "        Done."

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
echo "  Useful commands:"
echo "    Check status:    tailscale serve status"
echo "    Remove one:      sudo tailscale serve --https=<port> off"
echo "    Remove all:      sudo tailscale serve reset"
echo "    Re-run this:     sudo ./tailscale-serve.sh"
echo ""
echo "  NOTE: If services stop working after a reboot, run:"
echo "    cd ~/homelab && docker compose down && sudo tailscale serve reset"
echo "    && docker compose up -d && sudo ./tailscale-serve.sh"
echo ""