#!/bin/bash
# ============================================================
# Deploy-Script fuer Static File Publishing (Docker/Garage)
# Nutzung: ./deploy.sh <app-name> <build-verzeichnis> [--dry-run]
# Beispiel: ./deploy.sh app1 ./my-app/build
#           ./deploy.sh app1 ./my-app/build --dry-run
# ============================================================

set -euo pipefail

APP_NAME="${1:?Bitte App-Name angeben (z.B. app1)}"
BUILD_DIR="${2:?Bitte Build-Verzeichnis angeben (z.B. ./build)}"
DRY_RUN=""
if [[ "${3:-}" == "--dry-run" ]]; then
  DRY_RUN="--dryrun"
  echo "DRY RUN – es werden keine Aenderungen vorgenommen"
  echo ""
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# .env laden
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  echo "Fehler: ${SCRIPT_DIR}/.env nicht gefunden."
  echo "Bitte erst anlegen: cp .env.example .env"
  exit 1
fi
source "${SCRIPT_DIR}/.env"

BUCKET_NAME="${BUCKET_NAME:-static-publishing}"
S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:3900}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Fehler: Build-Verzeichnis '${BUILD_DIR}' existiert nicht."
  exit 1
fi

echo "Deploying '${APP_NAME}' aus '${BUILD_DIR}' ..."
echo "   Bucket:   ${BUCKET_NAME}"
echo "   Endpoint: ${S3_ENDPOINT}"
echo ""

# Dateien synchronisieren
aws s3 sync "${BUILD_DIR}" "s3://${BUCKET_NAME}/${APP_NAME}/" \
  --endpoint-url "${S3_ENDPOINT}" \
  --delete \
  --cache-control "public, max-age=3600" \
  ${DRY_RUN}

# HTML-Dateien mit kuerzerem Cache
aws s3 sync "${BUILD_DIR}" "s3://${BUCKET_NAME}/${APP_NAME}/" \
  --endpoint-url "${S3_ENDPOINT}" \
  --exclude "*" \
  --include "*.html" \
  --cache-control "public, max-age=60" \
  ${DRY_RUN}

if [[ -n "${DRY_RUN}" ]]; then
  echo ""
  echo "DRY RUN abgeschlossen – keine Dateien uebertragen."
  exit 0
fi

DOMAIN_NAME="${DOMAIN_NAME:-localhost:3902}"
echo ""
echo "Fertig! Erreichbar unter:"
echo "   https://${DOMAIN_NAME}/${APP_NAME}/"
