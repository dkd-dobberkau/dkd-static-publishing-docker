# Static Publishing Admin

Leichtgewichtiges Admin-Interface für das S3-basierte Static Publishing.
ZIP hochladen, App benennen, fertig.

## Features

- ZIP-Upload per Drag & Drop oder Datei-Dialog
- Automatische Erkennung von Root-Ordnern in ZIPs
- Bestehende Apps auflisten mit Größe, Dateianzahl, letzter Änderung
- Clean-Deploy (alte Dateien löschen vor Upload)
- CloudFront-Cache-Invalidierung pro App
- Apps löschen
- Korrektes Content-Type-Mapping und Cache-Control-Header
- Optionale Token-basierte Authentifizierung

## Starten

### Mit Docker Compose

```bash
# .env anlegen oder Variablen exportieren
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export CF_DISTRIBUTION_ID=...  # aus Terraform-Output

docker compose up -d
```

Admin ist dann unter http://localhost:8000 erreichbar.

### Lokal ohne Docker

```bash
pip install -r requirements.txt

export S3_BUCKET=static-publishing
export CF_DISTRIBUTION_ID=...
export DOMAIN=static.example.com
export AWS_REGION=eu-central-1

uvicorn app:app --host 0.0.0.0 --port 8000
```

## Authentifizierung

Optional per Token. In der `docker-compose.yml` setzen:

```yaml
- ADMIN_TOKEN=ein-sicherer-token
```

Dann muss bei API-Calls der Header `X-Admin-Token` mitgeschickt werden.
Die Web-Oberfläche lädt ohne Token, aber Schreiboperationen
(Deploy, Delete, Invalidate) erfordern ihn.

## API

| Methode | Pfad | Beschreibung |
|---------|------|--------------|
| GET | `/api/apps` | Alle Apps auflisten |
| POST | `/api/apps/{name}/deploy` | ZIP deployen (multipart, `file` + `clean`) |
| DELETE | `/api/apps/{name}` | App löschen |
| POST | `/api/apps/{name}/invalidate` | CloudFront-Cache invalidieren |
| GET | `/health` | Health-Check |

## AWS-Berechtigungen

Der Container braucht einen IAM-User oder eine Rolle mit:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::static-publishing",
        "arn:aws:s3:::static-publishing/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DISTRIBUTION_ID"
    }
  ]
}
```
