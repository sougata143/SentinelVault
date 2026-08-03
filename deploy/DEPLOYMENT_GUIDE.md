# SentinelVault — Production Deployment Guide (Oracle Cloud Free Tier)

## 1. Provision the VM

- **Shape**: Ampere A1 (ARM), 4 OCPU / 24GB RAM — the full free allowance
  as one instance. Comfortably runs Postgres, Redis, all four backend
  services, and Caddy on one box.
- **Image**: Ubuntu 24.04 (ARM64/aarch64 build — Ampere is ARM, not x86).
- **Boot volume**: default (part of the 200GB free block storage
  allowance) is plenty.
- Add your SSH key during creation (OCI won't let you in otherwise).

## 2. Networking — two firewalls to open, not just one

This is the single most common Oracle Cloud gotcha: there are **two
separate firewalls** and both must allow 80/443, or nothing works.

**a) OCI Security List / Network Security Group** (console-level):
Add Ingress Rules for the VM's subnet:
- Source `0.0.0.0/0`, TCP, destination port `80`
- Source `0.0.0.0/0`, TCP, destination port `443`
- (port 22/SSH is usually already open by default)

**b) The VM's own OS-level firewall** (iptables, pre-configured by
Oracle's Ubuntu image to block everything except a few defaults — this
is the part people usually forget):
```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

## 3. DNS

Point these at your VM's public IP (A records):
```
vault.yourdomain.com
api-auth.vault.yourdomain.com
api-sync.vault.yourdomain.com
api-security.vault.yourdomain.com
api-sharing.vault.yourdomain.com
```
(Or one wildcard `*.vault.yourdomain.com` record instead of four
separate `api-*` entries, if your DNS provider supports it — simpler,
same effect.)

## 4. Install Docker on the VM

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

## 5. Get the code onto the VM

```bash
git clone <your-repo-url> ~/sentinelvault
cd ~/sentinelvault
```

## 6. Production secrets — do not reuse dev values

Generate real secrets, don't ship with the placeholders:
```bash
openssl rand -hex 32   # use this output for JWT_SECRET
openssl rand -hex 24   # use this output for POSTGRES_PASSWORD
```
Create `.env` on the VM (copy from `.env.example`, then fill in):
- `JWT_SECRET` → the first generated value above
- `POSTGRES_PASSWORD` → the second generated value above
- `CORS_ALLOWED_ORIGINS` → `https://vault.yourdomain.com` (the **web
  app's** origin — not the API subdomains themselves)
- Real `GEMINI_API_KEY` / `HIBP_API_KEY` / `VIRUSTOTAL_API_KEY` if you
  want those features live rather than static fallbacks.

## 7. Build the Flutter web app with production API URLs

On your Mac (not the VM — cross-compiling web doesn't need to happen
server-side):
```bash
cd app
flutter build web --release \
  --dart-define=AUTH_BASE_URL=https://api-auth.vault.yourdomain.com \
  --dart-define=SYNC_BASE_URL=https://api-sync.vault.yourdomain.com \
  --dart-define=SECURITY_BASE_URL=https://api-security.vault.yourdomain.com \
  --dart-define=SHARING_BASE_URL=https://api-sharing.vault.yourdomain.com
```
Copy the output to the VM:
```bash
rsync -avz app/build/web/ your-user@your-vm-ip:~/sentinelvault/app/build/web/
```

## 8. Start everything

```bash
cd ~/sentinelvault
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f deploy/docker-compose.caddy.yml up -d
```

## 9. Verify

```bash
docker compose -f docker-compose.prod.yml ps
curl -I https://vault.yourdomain.com
curl -I https://api-auth.vault.yourdomain.com/health
```
Then do a real signup/unlock through the actual URL in a browser —
same as the local E2E pass, but against the live domain.

## 10. Backups — this now holds real user data

See `deploy/backup-postgres.sh`. Set it up as a daily cron job:
```bash
crontab -e
# add:
0 3 * * * /home/ubuntu/sentinelvault/deploy/backup-postgres.sh >> /home/ubuntu/backup.log 2>&1
```
Backups land in `~/sentinelvault-backups/` by default — copy them
off-box periodically (e.g. to OCI Object Storage's free 10GB tier, or
just `scp` them to your Mac) since a backup that only lives on the same
VM as the database doesn't protect against VM loss.

## Ongoing: updating the deployment

```bash
cd ~/sentinelvault
git pull
docker compose -f docker-compose.prod.yml up -d --build
```
Rebuild and re-`rsync` the Flutter web build (step 7) only when
client-side code changed.
