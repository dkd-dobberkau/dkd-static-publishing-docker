#!/bin/bash
# ============================================================
# Einmal-Setup fuer Garage nach dem ersten Start
# Erstellt Layout, Bucket und API-Key
# Nutzung: ./init.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# .env laden
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  echo "Fehler: ${SCRIPT_DIR}/.env nicht gefunden."
  echo "Bitte erst anlegen: cp .env.example .env"
  exit 1
fi
source "${SCRIPT_DIR}/.env"

CONTAINER="staticpub-garage"
BUCKET_NAME="${BUCKET_NAME:-static-publishing}"

garage() {
  docker exec "${CONTAINER}" /garage "$@"
}

echo "=== Garage Einmal-Setup ==="
echo ""

# 1. Node-ID ermitteln
echo "1. Node-ID ermitteln ..."
NODE_ID=$(garage node id 2>/dev/null | head -1 | cut -d'@' -f1)
if [[ -z "${NODE_ID}" ]]; then
  echo "Fehler: Garage-Container nicht erreichbar. Ist 'docker compose up -d' gelaufen?"
  exit 1
fi
echo "   Node-ID: ${NODE_ID:0:16}..."

# 2. Layout zuweisen
echo "2. Layout zuweisen ..."
garage layout assign -z dc1 -c 1G "${NODE_ID}"
garage layout apply --version 1

echo "   Layout zugewiesen und angewendet."

# 3. Bucket erstellen
echo "3. Bucket '${BUCKET_NAME}' erstellen ..."
garage bucket create "${BUCKET_NAME}"
echo "   Bucket erstellt."

# 4. Website-Modus aktivieren
echo "4. Website-Modus aktivieren ..."
garage bucket website --allow "${BUCKET_NAME}"
echo "   Website-Modus aktiv."

# 5. API-Key erstellen
echo "5. API-Key erstellen ..."
KEY_OUTPUT=$(garage key create deploy-key)
ACCESS_KEY=$(echo "${KEY_OUTPUT}" | grep "Key ID" | awk '{print $NF}')
SECRET_KEY=$(echo "${KEY_OUTPUT}" | grep "Secret key" | awk '{print $NF}')

# 6. Berechtigung setzen
echo "6. Berechtigung fuer Bucket setzen ..."
garage bucket allow --read --write --owner "${BUCKET_NAME}" --key deploy-key
echo "   Berechtigung gesetzt."

echo ""
echo "=== Setup abgeschlossen ==="
echo ""
echo "Folgende Werte fuer deploy.sh in die .env eintragen:"
echo ""
echo "  AWS_ACCESS_KEY_ID=${ACCESS_KEY}"
echo "  AWS_SECRET_ACCESS_KEY=${SECRET_KEY}"
echo ""
echo "Oder direkt exportieren:"
echo ""
echo "  export AWS_ACCESS_KEY_ID=${ACCESS_KEY}"
echo "  export AWS_SECRET_ACCESS_KEY=${SECRET_KEY}"
echo ""
echo "Test mit:"
echo "  ./deploy.sh app1 /pfad/zum/build"
