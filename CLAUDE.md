# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted static file publishing stack using **Garage** (S3-compatible object storage with built-in web server, ~50MB RAM) and **Traefik** (reverse proxy with automatic Let's Encrypt SSL). Designed as a lightweight alternative to AWS S3 + CloudFront.

## Architecture

```
Internet --> Traefik (SSL/Let's Encrypt, Port 80+443)
                |
                +--> Garage s3_web (Port 3902, Static Hosting)
                |
localhost:3900 --> Garage S3 API (deploy.sh uploads here)
```

- Traefik terminates SSL via Let's Encrypt ACME HTTP challenge, redirects HTTP to HTTPS, and routes traffic to Garage's web endpoint (port 3902) based on the `DOMAIN_NAME` host label.
- Garage exposes three ports: **3900** (S3 API, bound to localhost only), **3902** (web serving), **3903** (admin/health API).
- Apps are deployed as prefixed paths in a single S3 bucket: `s3://{BUCKET_NAME}/{app-name}/`

## Commands

```bash
# Initial setup
cp .env.example .env            # then fill in values
docker compose up -d            # start all services
./init.sh                       # one-time Garage setup (layout, bucket, API key)

# Deploy a static app
./deploy.sh <app-name> <build-dir>            # e.g. ./deploy.sh app1 ./build
./deploy.sh <app-name> <build-dir> --dry-run  # preview without changes

# Operations
docker compose up -d garage     # local dev (no SSL, access via localhost:3902)
docker compose logs -f garage
docker compose logs -f traefik
docker exec staticpub-garage /garage status
docker exec staticpub-garage /garage bucket list
docker exec staticpub-garage /garage key list
```

## Key Configuration

| File | Purpose |
|------|---------|
| `.env` / `.env.example` | All environment variables (domain, secrets, AWS credentials) |
| `garage.toml` | Garage config: storage paths, S3 API, web, admin ports; secrets via env vars |
| `traefik/traefik.yml` | Traefik entrypoints, Let's Encrypt resolver, Docker provider |
| `docker-compose.yml` | Service definitions, Traefik labels for routing, volume mounts |

## Deploy Script Details

`deploy.sh` uses `aws s3 sync` against the local Garage S3 endpoint. It runs two sync passes:
1. All files with `Cache-Control: public, max-age=3600` (1h)
2. HTML files only with `Cache-Control: public, max-age=60` (1min)

The `--delete` flag removes files from the bucket that no longer exist in the build directory.

## SPA Limitation

Garage serves `index.html` for directory requests (`/app1/` -> `/app1/index.html`) but does **not** support catch-all fallback. Deep links like `/app1/dashboard` return 404. Use hash-routing (`/app1/#/route`) or add Nginx with `try_files` if client-side routing is needed.

## Language

All scripts, comments, and documentation are in German.
