# Maintenance

## 1. Domains not working but SSH login works
When Pi boots, Tailscale starts before Docker because it's a system service. When configured to serve Homepage over HTTPS on port 443, Tailscale automatically also grabs port 80 to redirect HTTP traffic to HTTPS. By the time Docker starts and Nginx Proxy Manager tries to bind port 80, it's already taken — so NPM fails. The container appears running but isn't actually doing anything, breaking all `.lab` domains.

The fix applied (tailscale-serve.sh) tells Tailscale to stop listening on port 80 entirely since it doesn't actually need it — devices connect directly over the HTTPS ports anyway. Nginx now gets port 80 on every boot, and the `.lab` domains work without needing manual recovery after every reboot or power cut.

But in case, it not works, stop all containers are start them manually. 
```bash
cd ~/HomeLab && \
docker compose down && \
sudo tailscale serve reset && \
docker compose up -d && \
sleep 5 && \
sudo ./tailscale-serve.sh
```

## 2. Folioman
### Setup Token
Folioman generates a setup token when installed for the first time. It is needed to create the account.
```bash
cd ~/folioman
docker compose -f server/docker-compose.yml logs app | grep -A4 "first-run setup"
```

### Update
Folioman updates are a `git pull` + rebuild. No settings changes needed since data lives in the Postgres volume and secrets live in `server/.env`, both of which are untouched by an update.

```bash
cd ~/folioman

# Pull latest code
git pull

# Rebuild and restart — down first to ensure clean state
docker compose -f server/docker-compose.yml down
docker compose -f server/docker-compose.yml up -d --build
```

Check the logs to confirm migrations run cleanly:

```bash
docker compose -f server/docker-compose.yml logs -f app
```

Migration output followed by the gunicorn server starting. Once `server-app-1` shows as healthy in:

```bash
docker compose -f server/docker-compose.yml ps
```

### Allowed Hosts
Folioman will only allow hosts from specific IP/address to access. To add to the list, do the following:

```bash
nano ~/folioman/server/.env
```

Find the `FOLIOMAN_ALLOWED_HOSTS` line and make sure it has all the required hosts: 
`FOLIOMAN_ALLOWED_HOSTS=portfolio.lab,192.168.1.2,homepi.darter-economy.ts.net,localhost,127.0.0.1`

Save. Then once the build finishes and containers start, the correct hosts are already in place.

---
If the app container already started with wrong hosts before you edited the file, just do:

```bash
cd ~/folioman
docker compose -f server/docker-compose.yml restart app
```

---
Hence, it is always good to check after an update if the hosts are present or not before rebuild:

```bash
grep ALLOWED_HOSTS ~/folioman/server/.env
```

### Delete DB & Restart
To clean the DB and restart, it needs to create the setup token to create a new account.

```bash
cd ~/folioman

# Stop all Folioman containers
docker compose -f server/docker-compose.yml down

# Remove the database volume explicitly
docker volume rm server_folioman_pgdata

# Start back up — Postgres reinitialises fresh, migrations run again
docker compose -f server/docker-compose.yml up -d
```

Get the new setup token after containers are healthy:

```bash
docker compose -f server/docker-compose.yml logs app | grep -A4 "first-run setup"
```

What gets removed:
1. All holdings, transactions, valuations, investors
2. Admin account and login

What remains the same:
1. The Docker image (no rebuild needed)
2. `server/.env` — all secrets including `FOLIOMAN_FERNET_KEY`
3. The Folioman codebase in `~/folioman`

## 3. Update Individual Service
For the main homelab stack (Homepage, Pi-hole, Portainer, etc.), update one service at a time:

```bash
cd ~/HomeLab

# Pull the latest image for just that service
docker compose pull <service-name>

# Restart just that container with the new image
docker compose up -d <service-name>
```

For example, to update just Homepage:

```bash
docker compose pull homepage
docker compose up -d homepage
```

Every other container keeps running untouched. The up -d on a single service only recreates that one container.

---
**Folioman (separate stack)-**

```bash
cd ~/folioman
git pull
docker compose -f server/docker-compose.yml up -d --build app
```

Only rebuilds and restarts the app container, leaving the db and scheduler running.

---
**Nginx Proxy Manager -**

For Nginx Proxy Manager specifically, be a bit more careful — it holds port 80 and 443. Updating it causes a few seconds of downtime for all `.lab` domains while it restarts. Still just one command but expect 10-15 seconds of inaccessibility.