#!/bin/bash
# ============================================================
# Einmal-Setup fuer Garage auf Mittwald Studio
# Erstellt Layout, Bucket, API-Key und Domain-Alias via SSH
# Nutzung: ./init-mittwald.sh
# Voraussetzung: mw login + SSH-Key bei Mittwald hinterlegt
# ============================================================

set -euo pipefail

BUCKET_NAME="${BUCKET_NAME:-static-publishing}"

# SSH-Verbindungsdaten aus mw CLI ermitteln
echo "SSH-Verbindungsdaten ermitteln ..."
SSH_INFO=$(mw container list -o json | python3 -c "
import sys, json
containers = json.load(sys.stdin)
if not containers:
    print('ERROR: Keine Container gefunden', file=sys.stderr)
    sys.exit(1)
c = containers[0]
print(c['shortId'])
")

SSH_HOST="ssh.$(mw server list -o json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['clusterName'])").project.host"
SSH_USER=$(mw container ssh "${SSH_INFO}" --info 2>&1 | grep username | sed "s/.*'\\(.*\\)'/\\1/")

echo "   Host: ${SSH_HOST}"
echo "   User: ${SSH_USER}"

garage() {
  ssh -i ~/.ssh/id_ed25519 "${SSH_USER}@${SSH_HOST}" /garage "$@"
}

echo ""
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

# 7. Domain-Alias erstellen
echo "7. Domain-Alias erstellen ..."
MITTWALD_HOSTNAME=$(mw domain virtualhost list -o json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['hostname'])")
SUBDOMAIN=$(echo "${MITTWALD_HOSTNAME}" | cut -d'.' -f1)
garage bucket alias "${BUCKET_NAME}" "${SUBDOMAIN}"
echo "   Alias '${SUBDOMAIN}' fuer Bucket '${BUCKET_NAME}' erstellt."

echo ""
echo "=== Setup abgeschlossen ==="
echo ""
echo "AWS-Credentials fuer deploy.sh:"
echo ""
echo "  AWS_ACCESS_KEY_ID=${ACCESS_KEY}"
echo "  AWS_SECRET_ACCESS_KEY=${SECRET_KEY}"
echo ""
echo "Zum Deployen von lokal (Port-Forward noetig):"
echo ""
echo "  mw container port-forward ${SSH_INFO} 3900:3900 --ssh-identity-file ~/.ssh/id_ed25519"
echo "  AWS_ACCESS_KEY_ID=${ACCESS_KEY} AWS_SECRET_ACCESS_KEY=${SECRET_KEY} ./deploy.sh app1 /pfad/zum/build"
echo ""
echo "Erreichbar unter:"
echo "  https://${MITTWALD_HOSTNAME}/app1/"
