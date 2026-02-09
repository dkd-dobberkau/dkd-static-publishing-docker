# Docker-basiertes Static Publishing mit Garage + Traefik

Selbstgehostete Alternative zur AWS-Infrastruktur (S3 + CloudFront). Laeuft auf jedem Server mit Docker — z.B. Mittwald, Hetzner oder eigene Server.

## Architektur

```
Internet --> Traefik (SSL/Let's Encrypt, Port 80+443)
                |
                +--> Garage s3_web (Port 3902, Static Hosting)
                |
localhost:3900 --> Garage S3 API (fuer Deployments)
```

- **Traefik** — Reverse Proxy mit automatischen Let's Encrypt SSL-Zertifikaten
- **Garage** — S3-kompatibler Objektspeicher (~50MB RAM) mit eingebautem Webserver fuer statische Dateien

## Voraussetzungen

- Docker und Docker Compose
- AWS CLI (fuer `aws s3 sync` gegen Garage)
- Domain mit DNS-Zugriff (A-Record auf den Server)

## Einrichtung

### 1. Konfiguration

```bash
cd docker
cp .env.example .env
```

`.env` bearbeiten und Werte setzen:

```bash
DOMAIN_NAME=staticpub.dkd.de
ACME_EMAIL=admin@dkd.de
GARAGE_RPC_SECRET=$(openssl rand -hex 32)
GARAGE_ADMIN_TOKEN=$(openssl rand -hex 32)
BUCKET_NAME=static-publishing
```

### 2. DNS einrichten

A-Record fuer die Domain auf die IP des Servers setzen:

```
staticpub.dkd.de.  A  <SERVER-IP>
```

### 3. Container starten

```bash
docker compose up -d
```

### 4. Garage initialisieren (einmalig)

```bash
./init.sh
```

Das Script erstellt:
- Garage Storage Layout
- S3-Bucket mit Website-Modus
- API-Key fuer Deployments

Die ausgegebenen AWS-Credentials in die `.env` eintragen oder als Umgebungsvariablen exportieren.

### 5. App deployen

```bash
./deploy.sh app1 /pfad/zum/build
```

## Befehle

```bash
# Container starten
docker compose up -d

# Container stoppen
docker compose down

# Logs anzeigen
docker compose logs -f
docker compose logs -f garage
docker compose logs -f traefik

# App deployen
./deploy.sh <app-name> <build-verzeichnis>
./deploy.sh <app-name> <build-verzeichnis> --dry-run

# Garage-Status pruefen
docker exec staticpub-garage /garage status

# Buckets auflisten
docker exec staticpub-garage /garage bucket list

# Keys auflisten
docker exec staticpub-garage /garage key list
```

## Vergleich AWS vs. Docker

| Feature | AWS | Docker |
|---------|-----|--------|
| S3-Speicher | AWS S3 | Garage (S3-kompatibel) |
| Webserver | CloudFront | Garage s3_web |
| SPA index.html | CloudFront Function | Garage `index = "index.html"` |
| HTTPS | ACM-Zertifikat | Let's Encrypt via Traefik |
| Deploy | `aws s3 sync` gegen AWS | `aws s3 sync` gegen Garage-Endpoint |
| Cache-Invalidierung | CloudFront Invalidation | Nicht noetig (kein CDN-Cache) |

## SPA-Routing

Garage liefert `index.html` automatisch fuer Verzeichnisse (`/app1/` -> `/app1/index.html`). Fuer SPAs mit Client-Side-Routing (z.B. `/app1/dashboard`) gibt es Einschraenkungen:

- **Deep-Links ohne Extension** (`/app1/route`) fuehren zu einem 404, da Garage keinen automatischen Fallback auf `index.html` macht
- **Loesung 1 (empfohlen):** Hash-Routing verwenden (`/app1/#/route`) — funktioniert ohne Server-Anpassung
- **Loesung 2:** Nginx als Proxy vor Garage mit `try_files`-Fallback (nur wenn noetig)

## Dateien

| Datei | Zweck |
|-------|-------|
| `docker-compose.yml` | Traefik + Garage Services |
| `.env.example` | Konfigurationsvorlage |
| `garage.toml` | Garage-Konfiguration (S3 API, Web, Admin) |
| `traefik/traefik.yml` | Traefik-Konfiguration (Let's Encrypt, Docker Provider) |
| `init.sh` | Einmal-Setup: Layout, Bucket, Key erstellen |
| `deploy.sh` | Deploy via `aws s3 sync` gegen Garage |

## Lokale Entwicklung

Fuer lokale Tests ohne SSL kann Traefik uebersprungen werden:

```bash
# Nur Garage starten
docker compose up -d garage

# Direkt auf Garage-Web zugreifen
curl http://localhost:3902/app1/
```
