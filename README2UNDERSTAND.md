# Home Lab — Raspberry Pi 4

A self-hosted home lab running on a Raspberry Pi 4, providing network services, monitoring, file management, remote access, and network printing for all devices in the home.

---

## Network Layout

| Device | IP | Role |
|---|---|---|
| ISP Router | `192.168.1.1` | DHCP server, internet gateway |
| Raspberry Pi | `192.168.1.2` | HomeLab - static IP |
| TP-Link Router | `192.168.1.3` | Personal router in AP/bridge mode (no NAT) |
| Other devices | `192.168.1.x` | All on the same flat subnet |

All devices get IPs from the ISP router's DHCP. The personal router acts as a WiFi access point only — no double NAT.

DNS for all devices is handled by Pi-hole at `192.168.1.2`. Set this in the ISP router's DHCP settings.

---

## Local Services

| Service | Local URL | Port | Purpose |
|---|---|---|---|
| Homepage | `http://home.lab` | 3000 | Dashboard for all services |
| Pi-hole | `http://pihole.lab/admin` | 8053 | DNS + ad blocking |
| Portainer | `http://portainer.lab` | 9000 | Docker container management |
| Nginx Proxy Manager | `http://proxy.lab` | 81 (admin) | Reverse proxy for *.lab domains |
| Uptime Kuma | `http://uptime.lab` | 3001 | Uptime monitoring & alerts |
| Dozzle | `http://logs.lab` | 8080 | Docker container log viewer |
| Netdata | `http://stats.lab` | 19999 | System stats (CPU, RAM, temp, disk) |
| File Browser | `http://files.lab` | 8085 | Web-based file manager |
| CUPS | `http://192.168.1.2:631` | 631 | Network print server |
| Folioman | `http://portfolio.lab` | 8000 | Mutual fund portfolio tracker |

---

## Remote Access

**Tailscale** is installed on the Pi as a host service (not Docker). It provides:
- SSH from anywhere: `ssh soham@homepi.darter-economy.ts.net`
- Web UI access via Tailscale IP or hostname + port
- Split DNS: `.lab` domains resolve correctly on any Tailscale-connected device
- Subnet Routing:  Tells Tailscale to route all traffic destined for 192.168.1.0/24 through the Pi. Needed for remote access using `.lab` domains.

**Tailscale Serve** maps services to HTTPS URLs on the Tailscale network:

| Service | Tailscale URL |
|---|---|
| Homepage | `https://homepi.darter-economy.ts.net` |
| Portainer | `https://homepi.darter-economy.ts.net:9000` |
| Pi-hole | `https://homepi.darter-economy.ts.net:8054` |
| Uptime Kuma | `https://homepi.darter-economy.ts.net:3001` |
| Dozzle | `https://homepi.darter-economy.ts.net:8080` |
| Netdata | `https://homepi.darter-economy.ts.net:19999` |
| File Browser | `https://homepi.darter-economy.ts.net:8085` |
| Folioman | `https://homepi.darter-economy.ts.net:8001` |
| CUPS | `https://homepi.darter-economy.ts.net:8632` |

---

## Subnet Routing via Tailscale

By default, Tailscale only makes the Pi itself reachable remotely — not the rest of the home network. Enabling subnet routing tells Tailscale to route all traffic destined for `192.168.1.0/24` through the Pi, making every device on the home network accessible remotely, including the ISP router (`192.168.1.1`), TP-Link router (`192.168.1.3`), and any other device.

This also means `.lab` domains resolve and connect correctly over Tailscale since `192.168.1.2` becomes reachable from anywhere, exactly as it is on the home network.

### Setup (one time)

**On the Pi:**
```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

**In the Tailscale dashboard:**
1. Go to [login.tailscale.com](https://login.tailscale.com) → Machines → click your Pi
2. Under Subnets → click **Approve** next to `192.168.1.0/24`

**On each remote device:**
- Open the Tailscale app → enable **Use Tailscale subnets** (on some platforms this is automatic)

### What becomes accessible remotely

Once enabled, the following are all reachable from any Tailscale-connected device, from anywhere:

| Address | Device |
|---|---|
| `192.168.1.1` | ISP router admin page |
| `192.168.1.2` | Raspberry Pi — all services and `.lab` URLs |
| `192.168.1.3` | TP-Link router admin page |
| `192.168.1.x` | Any other device on the home network |

### Note on DNS

With subnet routing active, Pi-hole local DNS records should point to `192.168.1.2` (not the Tailscale IP). Remote devices resolve `.lab` domains to `192.168.1.2` via Pi-hole, and Tailscale subnet routing ensures that IP is reachable — so the connection completes correctly end to end.

---

## Network Printing

An **Epson L3110** is connected to the Pi via USB and shared over the network via CUPS.

| Platform | How to print |
|---|---|
| iPhone / iPad | AirPrint — appears automatically in Print dialog, no setup needed |
| Mac | System Settings → Printers & Scanners → Add — auto-discovered |
| Windows | Settings → Printers & Scanners → Add device — auto-discovered via Samba |
| Android | Install Mopria Print Service → add printer at `192.168.1.2` |

---

## Remote Printing via Tailscale

Tailscale must be **active and connected** on your device before printing. The printer is shared via CUPS over IPP — Tailscale makes it reachable from anywhere.

### iPhone / iPad
Nothing extra to configure. As long as Tailscale is active on your phone and Split DNS is set up for `.lab`, AirPrint finds `Epson L3110 @ homepi` automatically in the Print dialog — even away from home.

### Mac
One-time setup:
1. System Settings → Printers & Scanners → click `+`
2. Click the **IP** tab
3. Fill in:
   - Protocol: `IPP`
   - Address: `homepi.darter-economy.ts.net`
   - Queue: `printers/Epson-L3110`
   - Name: `Epson L3110 (Remote)`
4. macOS detects the driver automatically

Works whenever Tailscale is active on the Mac.

### Windows
One-time setup:
1. Settings → Bluetooth & devices → Printers & scanners → Add device → **Add manually**
2. Choose **Add a printer using a TCP/IP address or hostname**
3. Enter hostname: `homepi.darter-economy.ts.net` and port: `631`
4. Select Epson L3110 driver when prompted

Or use the direct IPP URL — choose **Add a printer using an IP address** and enter:
```
http://homepi.darter-economy.ts.net:631/printers/Epson-L3110
```

Works whenever Tailscale is running on the laptop.

### Android
1. Install **Mopria Print Service** from Play Store
2. Open Mopria settings → Add printer manually
3. Enter: `http://homepi.darter-economy.ts.net:631/printers/Epson-L3110`

### Managing the print queue remotely
Visit the CUPS web UI from anywhere via Tailscale:
```
https://homepi.darter-economy.ts.net:631
```
From here you can view the queue, cancel jobs, and check printer status.

---

## Folioman — Mutual Fund Portfolio Tracker

[Folioman](https://github.com/codereverser/folioman) tracks Indian mutual fund holdings, valuations, and capital gains. It runs as its **own separate stack** — not part of the main `docker-compose.yml` — because it ships its own compose file and is built from source rather than pulled as a pre-built image.

**Location on the Pi:** `~/folioman`
**Stack file:** `~/folioman/server/docker-compose.yml`
**Local URL:** `http://portfolio.lab` (proxied to port 8000)

### What it runs
Three containers, separate from the main homelab stack:
- **app** — the web UI and API (Django)
- **scheduler** — keeps NAVs and valuations fresh (must never be scaled past one instance)
- **db** — Postgres 17 with a persistent volume

### Setup — handled automatically by setup.sh
`setup.sh` clones the repo, generates the required secrets (`FOLIOMAN_SECRET_KEY`, `FOLIOMAN_FERNET_KEY`, `FOLIOMAN_DB_PASSWORD`), sets `FOLIOMAN_ALLOWED_HOSTS` to cover local, Tailscale, and `.lab` access, and starts the stack with `docker compose up -d --build`.

### Manual step — create your admin account
On first run, a one-time setup token is printed to the app's logs:
```bash
cd ~/folioman
docker compose -f server/docker-compose.yml logs app | grep -A4 "first-run setup"
```
Visit `http://portfolio.lab`, enter the token on the setup screen, and create your admin account.

### ⚠️ Critical — back up FOLIOMAN_FERNET_KEY separately
This key encrypts PANs at rest in the database. **If it's lost, encrypted PAN data becomes permanently unrecoverable** — there is no recovery path. It lives in `~/folioman/server/.env`.

Back it up somewhere other than the Pi itself — e.g. copy it into File Browser and download it, or store it in a password manager. Do this once, right after first setup.

### Day-to-day commands
```bash
cd ~/folioman

# Logs
docker compose -f server/docker-compose.yml logs -f app
docker compose -f server/docker-compose.yml logs -f scheduler

# Stop / start (keeps data)
docker compose -f server/docker-compose.yml down
docker compose -f server/docker-compose.yml up -d

# Upgrade
git pull
docker compose -f server/docker-compose.yml up -d --build

# Reset forgotten password
docker compose -f server/docker-compose.yml exec app django-admin changepassword <username>
```

### Backups
Your data lives in two places — back up both, separately from each other:

```bash
# Database dump
docker compose -f server/docker-compose.yml exec db \
    pg_dump -U folioman folioman > folioman-backup.sql
```

- The **database dump** above (holdings, transactions, valuations)
- **`FOLIOMAN_FERNET_KEY`** from `server/.env` — store it somewhere safe and separate from the Pi

To restore: bring up a fresh stack with the **same** `FOLIOMAN_FERNET_KEY`, then `psql … < folioman-backup.sql`. A database dump restored with a different key leaves PANs unrecoverable.

### Removing Folioman
Because of the irreversible data risk, `teardown.sh` **never removes Folioman automatically**. It asks separately, with its own explicit `DELETE` confirmation, before touching it in any way.

---

## SD Card Protection

**log2ram** is installed to reduce SD card wear. It moves `/var/log` to RAM and syncs to disk once daily. If the Pi loses power unexpectedly, that day's logs may be lost — acceptable trade-off for a home lab.

- Size: 128MB RAM allocated for logs
- Journald capped at 64MB
- Verify after reboot: `sudo systemctl status log2ram`

---

## Files in This Repo

```
homelab/
├── docker-compose.yml          # All Docker services defined here
├── setup.sh                    # One-command bootstrap for fresh Pi OS install
├── teardown.sh                 # Remove all services cleanly
├── tailscale-serve.sh          # Set up Tailscale Serve for all web UIs
├── README.md                   # This file
├── nginx/
│   ├── data/                   # Nginx Proxy Manager config (auto-generated)
│   └── letsencrypt/            # SSL certs (auto-generated)
├── homepage/
│   └── config/
│       ├── services.yaml       # Service tiles and links
│       ├── widgets.yaml        # Header widgets (weather, stats, search)
│       ├── settings.yaml       # Theme, background, layout
│       └── images/
│           └── background.jpg  # Background image (copy manually)
└── filebrowser/
    ├── filebrowser.db          # File Browser database (auto-created)
    └── settings.json           # File Browser config (auto-created)

folioman/                       # SEPARATE repo, cloned independently by setup.sh
├── server/
│   ├── docker-compose.yml      # Folioman's own stack (app, scheduler, db)
│   ├── .env                    # Secrets — FOLIOMAN_FERNET_KEY lives here, back up separately
│   └── .env.example
```

---

## Fresh Install — Step by Step

### Before running setup.sh

Edit `docker-compose.yml` and change:
- `FTLCONF_webserver_api_password: "changeme"` → your Pi-hole password

### Run setup

```bash
git clone https://github.com/sohamlive/HomeLab.git
cd HomeLab
chmod +x setup.sh teardown.sh tailscale-serve.sh
sudo ./setup.sh
```

### After setup.sh completes — reboot first

```bash
sudo reboot
```

log2ram requires a reboot to activate. SSH back in after ~30 seconds.

---

## Manual Steps (do these once after first boot)

These cannot be automated and must be done manually.

### 1. Nginx Proxy Manager — configure *.lab routes

Visit `http://192.168.1.2:81`
Default login: `admin@example.com` / `changeme` (change immediately)

Add a proxy host for each service:

| Domain | Forward IP | Forward Port |
|---|---|---|
| `home.lab` | `192.168.1.2` | `3000` |
| `pihole.lab` | `192.168.1.2` | `8053` |
| `portainer.lab` | `192.168.1.2` | `9000` |
| `uptime.lab` | `192.168.1.2` | `3001` |
| `logs.lab` | `192.168.1.2` | `8080` |
| `stats.lab` | `192.168.1.2` | `19999` |
| `files.lab` | `192.168.1.2` | `8085` |
| `proxy.lab` | `192.168.1.2` | `81` |
| `portfolio.lab` | `192.168.1.2` | `8000` |

### 2. ISP router — set DNS to Pi-hole

Log into `http://192.168.1.1` → find DHCP settings → set:
- Primary DNS: `192.168.1.2`
- Secondary DNS: `1.1.1.1` (fallback if Pi goes down)

This makes every device on the network use Pi-hole for DNS automatically.

### 3. Tailscale — install and connect

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Visit the URL it prints to authenticate
tailscale ip   # note your Tailscale IP (100.x.x.x)
```

Install Tailscale on your phone and laptop too — log in with the same account.

### 4. Tailscale dashboard — enable HTTPS and Split DNS

Go to [login.tailscale.com](https://login.tailscale.com):

**Enable HTTPS certificates:**
DNS → Enable HTTPS Certificates → Enable

**Enable Split DNS for .lab domains:**
DNS → Nameservers → Add nameserver → Custom
- IP: your Pi's Tailscale IP (`100.107.90.44`)
- Tick: Restrict to domain
- Domain: `lab`
- Save

This makes `.lab` URLs resolve correctly on any Tailscale-connected device, anywhere.

### 5. Tailscale Serve — enable web UI access from anywhere

```bash
chmod +x tailscale-serve.sh
sudo ./tailscale-serve.sh
```

### 6. CUPS — add the Epson L3110 printer

Make sure the printer is plugged into the Pi's USB port, then:

1. Visit `http://192.168.1.2:631`
2. Administration → Add Printer
3. Login with your Pi username and password
4. Select the Epson L3110 from Local Printers
   - If it shows a Connection input instead, paste:
     ```
     usb://EPSON/L3110%20Series?serial=5836484E3131313489&interface=1
     ```
5. Name it `Epson-L3110`, tick **Share This Printer**
6. Select driver: `EPSON-ESC/P-R Printer Driver for Linux`
7. Set default options: A4, Standard quality
8. Administration → Manage Printer → tick **Share**

Test with: Administration → Print Test Page

### 7. File Browser — change default password

Visit `http://192.168.1.2:8085`
Login: `admin` / `admin`
Settings → User Management → change password immediately

### 8. Homepage — update Pi-hole widget key

Edit `~/homelab/homepage/config/services.yaml`:
Replace `YOUR_PIHOLE_PASSWORD_HERE` with your actual Pi-hole password.

Or get a dedicated app password from:
Pi-hole admin → Settings → Web interface/API → Expert mode → Configure app password

### 9. Homepage — add background image

```bash
scp your-image.jpg soham@192.168.1.2:~/homelab/homepage/config/images/background.jpg
```

Homepage picks it up immediately on next browser refresh.

### 10. Folioman — create admin account and back up the Fernet key

```bash
cd ~/folioman
docker compose -f server/docker-compose.yml logs app | grep -A4 "first-run setup"
```
Visit `http://portfolio.lab`, enter the token, create your admin account.

Then back up `FOLIOMAN_FERNET_KEY` from `~/folioman/server/.env` somewhere safe and separate from the Pi. See the [Folioman section](#folioman--mutual-fund-portfolio-tracker) above for why this matters.

### 11. FileBrowser - get first password to change it

FileBrowser generates a default first password which is needed to access the service for the first time. If lost, the database needs to be created again. This is how you can get the password - 

```bash
docker logs filebrowser 2>&1 | grep -i "password"
```

---

## Day-to-Day Usage

**Start all services** (after teardown or manual stop):
```bash
cd ~/HomeLab
docker compose up -d
```

**Stop all services:**
```bash
docker compose down
```

**Restart a single service:**
```bash
docker compose restart homepage
```

**Update a service to latest image:**
```bash
docker compose pull homepage
docker compose up -d homepage
```

**Or use Portainer** at `http://portainer.lab` for all of the above without SSH.

**Check log2ram status:**
```bash
sudo systemctl status log2ram
```

**Full teardown (removes everything, keeps Docker and Tailscale):**
```bash
sudo ./teardown.sh
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Homepage shows host validation error | Add the new hostname/IP to `HOMEPAGE_ALLOWED_HOSTS` in `docker-compose.yml` → restart homepage |
| Pi-hole wrong password | Run `docker exec -it pihole pihole setpasswd` |
| CUPS web UI disabled | Run `sudo cupsctl WebInterface=yes && sudo systemctl restart cups` |
| Printer not discovered on network | Run `avahi-browse _ipp._tcp --terminate` — check eth0 shows the printer |
| `.lab` domains not resolving remotely | Check Tailscale Split DNS is set to route `lab` to your Pi's Tailscale IP |
| log2ram not active | Reboot required — `sudo reboot` |
| File Browser won't start | Check `./filebrowser/filebrowser.db` exists (touch it if not) |
| SSH session drops during setup | Expected — static IP change restarts network. Reconnect to `192.168.1.2` |
| Folioman `app` exits, logs show `ImproperlyConfigured` | A required secret is missing in `~/folioman/server/.env` — check `FOLIOMAN_SECRET_KEY`, `FOLIOMAN_FERNET_KEY`, `FOLIOMAN_DB_PASSWORD` are all set |
| Folioman browser shows `Bad Request (400)` | The hostname isn't in `FOLIOMAN_ALLOWED_HOSTS` in `~/folioman/server/.env` — add it and restart |
| Folioman `/api/health` returns 503 | App can't reach Postgres — check the `db` service is healthy: `docker compose -f server/docker-compose.yml ps` |
| Folioman NAVs/valuations not updating | Check exactly one `scheduler` container is running |