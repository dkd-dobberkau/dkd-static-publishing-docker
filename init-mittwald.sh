#!/bin/bash
# ============================================================
# Einmal-Setup fuer Garage auf Mittwald Studio
# Erstellt Layout, Bucket und API-Key via mw container exec
# Nutzung: ./init-mittwald.sh <container-name>
# Beispiel: ./init-mittwald.sh garage
# ============================================================

set -euo pipefail

CONTAINER_NAME="${1:?Bitte Container-Name angeben (z.B. garage)}"
BUCKET_NAME="${BUCKET_NAME:-static-publishing}"

garage() {
  mw container exec "${CONTAINER_NAME}" -- /garage "$@"
}

echo "=== Garage Einmal-Setup (Mittwald) ==="
echo ""

# 1. Node-ID ermitteln
echo "1. Node-ID ermitteln ..."
NODE_ID=$(garage node id 2>/dev/null | head -1 | cut -d'@' -f1)
if [[ -z "${NODE_ID}" ]]; then
  echo "Fehler: Garage-Container nicht erreichbar."
  echo "Ist 'mw stack deploy' gelaufen und der Container gestartet?"
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
echo "Zum Deployen von lokal (Port-Forward noetig):"
echo ""
echo "  mw container port-forward ${CONTAINER_NAME} 3900:3900"
echo "  ./deploy.sh app1 /pfad/zum/build"
