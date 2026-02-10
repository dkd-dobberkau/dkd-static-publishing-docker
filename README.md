# Docker-basiertes Static Publishing mit Garage + Traefik

Selbstgehostete Alternative zur AWS-Infrastruktur (S3 + CloudFront). Laeuft auf jedem Server mit Docker — z.B. Mittwald, Hetzner oder eigene Server.

## Architektur

```
Internet --> Traefik (SSL/Let's Encrypt, Port 80+443)
                |
                +--> Garage s3_web (Port 3902, Static Hosting)
                |
                +--> Admin (Port 8000, /admin)
                |
localhost:3900 --> Garage S3 API (fuer Deployments)
```

- **Traefik** — Reverse Proxy mit automatischen Let's Encrypt SSL-Zertifikaten
- **Garage** — S3-kompatibler Objektspeicher (~50MB RAM) mit eingebautem Webserver fuer statische Dateien
- **Admin** — Web-Interface fuer ZIP-basiertes Deployment und App-Verwaltung

## Voraussetzungen

- Docker und Docker Compose
- AWS CLI (fuer `aws s3 sync` gegen Garage, alternativ Admin-Interface nutzen)
- Domain mit DNS-Zugriff (A-Record auf den Server)

## Einrichtung

### 1. Konfiguration

```bash
cp .env.example .env
```

`.env` bearbeiten und Werte setzen:

```bash
DOMAIN_NAME=static.example.com
ACME_EMAIL=admin@dkd.de
GARAGE_RPC_SECRET=$(openssl rand -hex 32)
GARAGE_ADMIN_TOKEN=$(openssl rand -hex 32)
BUCKET_NAME=static-publishing
ADMIN_TOKEN=$(openssl rand -hex 32)  # optional: schuetzt das Admin-Interface
```

### 2. DNS einrichten

A-Record fuer die Domain auf die IP des Servers setzen:

```
static.example.com.  A  <SERVER-IP>
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

Per CLI:

```bash
./deploy.sh app1 /pfad/zum/build
```

Oder per Admin-Interface: ZIP-Datei auf `https://<DOMAIN>/admin/` hochladen.

## Admin-Interface

Das Admin-Interface bietet eine Web-Oberflaeche fuer:

- **ZIP-Upload** — Ordner als ZIP packen und per Drag & Drop deployen
- **App-Uebersicht** — Alle deployed Apps mit Dateianzahl, Groesse und letztem Update
- **App loeschen** — Apps aus dem S3-Bucket entfernen

**App-Naming:** Beim ZIP-Upload wird aus dem Dateinamen automatisch ein App-Name vorgeschlagen (z.B. `Meine App_v2.zip` → `meine-app-v2`). Sonderzeichen werden durch Bindestriche ersetzt, alles wird in Kleinbuchstaben umgewandelt. Der vorgeschlagene Name kann vor dem Deploy im Textfeld angepasst werden.

Zugang ueber `https://<DOMAIN>/admin/` (mit Traefik) oder `http://localhost:8000` (lokal).

Wenn `ADMIN_USER` und `ADMIN_PASSWORD` gesetzt sind, wird das Admin-Interface per HTTP Basic Auth geschuetzt.

## Befehle

```bash
# Alle Services starten (Traefik + Garage + Admin)
docker compose up -d

# Nur Garage + Admin starten (ohne Traefik/SSL)
docker compose up -d garage admin

# Container stoppen
docker compose down

# Logs anzeigen
docker compose logs -f
docker compose logs -f garage
docker compose logs -f admin

# App deployen (CLI)
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
| Deploy | `aws s3 sync` gegen AWS | `aws s3 sync` gegen Garage oder Admin-ZIP-Upload |
| Admin-UI | AWS Console | Admin-Container |
| Cache-Invalidierung | CloudFront Invalidation | Nicht noetig (kein CDN-Cache) |

## SPA-Routing

Garage liefert `index.html` automatisch fuer Verzeichnisse (`/app1/` -> `/app1/index.html`). Fuer SPAs mit Client-Side-Routing (z.B. `/app1/dashboard`) gibt es Einschraenkungen:

- **Deep-Links ohne Extension** (`/app1/route`) fuehren zu einem 404, da Garage keinen automatischen Fallback auf `index.html` macht
- **Loesung 1 (empfohlen):** Hash-Routing verwenden (`/app1/#/route`) — funktioniert ohne Server-Anpassung
- **Loesung 2:** Nginx als Proxy vor Garage mit `try_files`-Fallback (nur wenn noetig)

## Dateien

| Datei | Zweck |
|-------|-------|
| `docker-compose.yml` | Traefik + Garage + Admin Services |
| `docker-compose.mittwald.yml` | Garage + Admin fuer Mittwald Studio |
| `.env.example` | Konfigurationsvorlage |
| `garage.toml` | Garage-Konfiguration (S3 API, Web, Admin) |
| `traefik/traefik.yml` | Traefik-Konfiguration (Let's Encrypt, Docker Provider) |
| `admin-container/` | Admin-Interface (FastAPI, Dockerfile, Templates) |
| `init.sh` | Einmal-Setup: Layout, Bucket, Key erstellen |
| `deploy.sh` | Deploy via `aws s3 sync` gegen Garage |

## Lokale Entwicklung

Fuer lokale Tests ohne SSL kann Traefik uebersprungen werden:

```bash
# Garage + Admin starten
docker compose up -d garage admin

# Admin-Interface
open http://localhost:8000

# Direkt auf Garage-Web zugreifen
curl http://localhost:3902/app1/
```

## Mittwald Studio Deployment

Separate Compose-Datei fuer Mittwald Container Hosting (kein Traefik — SSL/Ingress uebernimmt Mittwald):

```bash
# Image bauen und pushen
docker buildx build --platform linux/amd64 -t olivierdo/staticpub-admin:latest ./admin-container
docker push olivierdo/staticpub-admin:latest

# Auf Mittwald starten
docker compose -f docker-compose.mittwald.yml up -d
```

| Datei | Zweck |
|-------|-------|
| `docker-compose.mittwald.yml` | Garage + Admin Stack fuer Mittwald |
| `garage.mittwald.toml` | Garage-Config mit Mittwald `root_domain` |
| `Dockerfile.mittwald` | Garage-Image mit eingebetteter Config |
| `init-mittwald.sh` | Einmal-Setup via SSH |
| `.env.mittwald` | Mittwald-spezifische Secrets |
