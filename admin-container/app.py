"""
Static Publishing Admin – Lightweight admin interface for S3-based static hosting.
Single-file FastAPI backend. Run with: uvicorn app:app --host 0.0.0.0 --port 8000
"""

import os
import io
import zipfile
import asyncio
from datetime import datetime, timezone
from pathlib import PurePosixPath

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

# ---------------------------------------------------------------------------
# Config from environment
# ---------------------------------------------------------------------------
S3_BUCKET = os.environ.get("S3_BUCKET", "dkd-static-publishing")
S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "")
CF_DISTRIBUTION_ID = os.environ.get("CF_DISTRIBUTION_ID", "")
AWS_REGION = os.environ.get("AWS_REGION", "garage")
DOMAIN = os.environ.get("DOMAIN", "staticpub.dkd.de")
APP_PREFIX = os.environ.get("APP_PREFIX", "")  # z.B. "/admin" fuer Pfad-basiertes Routing
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "")  # optional simple auth

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
s3_kwargs = {"region_name": AWS_REGION}
if S3_ENDPOINT:
    s3_kwargs["endpoint_url"] = S3_ENDPOINT
    s3_kwargs["config"] = BotoConfig(s3={"addressing_style": "path"})
s3 = boto3.client("s3", **s3_kwargs)
cf = boto3.client("cloudfront") if CF_DISTRIBUTION_ID else None

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Static Publishing Admin", version="1.0.0")

# Statische Dateien unter APP_PREFIX mounten
app.mount(f"{APP_PREFIX}/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

MIME_MAP = {
    ".html": "text/html",
    ".htm": "text/html",
    ".css": "text/css",
    ".js": "application/javascript",
    ".mjs": "application/javascript",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
    ".ico": "image/x-icon",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".eot": "application/vnd.ms-fontobject",
    ".otf": "font/otf",
    ".xml": "application/xml",
    ".txt": "text/plain",
    ".md": "text/markdown",
    ".pdf": "application/pdf",
    ".map": "application/json",
    ".webmanifest": "application/manifest+json",
}


def guess_content_type(filename: str) -> str:
    suffix = PurePosixPath(filename).suffix.lower()
    return MIME_MAP.get(suffix, "application/octet-stream")


def cache_control_for(filename: str) -> str:
    suffix = PurePosixPath(filename).suffix.lower()
    if suffix in (".html", ".htm"):
        return "public, max-age=60"
    if suffix in (".json", ".xml", ".webmanifest"):
        return "public, max-age=300"
    return "public, max-age=31536000, immutable"


def list_apps() -> list[dict]:
    """List top-level 'folders' in the bucket (= apps)."""
    apps = {}
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=S3_BUCKET, Delimiter="/"):
        for prefix in page.get("CommonPrefixes", []):
            app_name = prefix["Prefix"].rstrip("/")
            apps[app_name] = {"name": app_name, "file_count": 0, "total_size": 0}

    # Get file counts and sizes
    for app_name in apps:
        for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=f"{app_name}/"):
            for obj in page.get("Contents", []):
                apps[app_name]["file_count"] += 1
                apps[app_name]["total_size"] += obj.get("Size", 0)
                # Track latest modification
                mod = obj.get("LastModified")
                if mod:
                    prev = apps[app_name].get("last_modified")
                    if not prev or mod > prev:
                        apps[app_name]["last_modified"] = mod

    result = sorted(apps.values(), key=lambda a: a["name"])
    for a in result:
        a["total_size_human"] = _human_size(a["total_size"])
        if a.get("last_modified"):
            a["last_modified_human"] = a["last_modified"].strftime("%Y-%m-%d %H:%M")
        else:
            a["last_modified_human"] = "–"
        a["url"] = f"https://{DOMAIN}/{a['name']}/"
    return result


def _human_size(num_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if num_bytes < 1024:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.1f} TB"


def invalidate_cache(app_name: str):
    """Invalidate CloudFront cache for an app."""
    if not cf or not CF_DISTRIBUTION_ID:
        return
    try:
        cf.create_invalidation(
            DistributionId=CF_DISTRIBUTION_ID,
            InvalidationBatch={
                "Paths": {"Quantity": 1, "Items": [f"/{app_name}/*"]},
                "CallerReference": f"{app_name}-{datetime.now(timezone.utc).isoformat()}",
            },
        )
    except ClientError:
        pass  # non-critical


def delete_app_from_s3(app_name: str) -> int:
    """Delete all objects under an app prefix. Returns count of deleted objects."""
    deleted = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=f"{app_name}/"):
        objects = [{"Key": obj["Key"]} for obj in page.get("Contents", [])]
        if objects:
            s3.delete_objects(Bucket=S3_BUCKET, Delete={"Objects": objects})
            deleted += len(objects)
    return deleted


# ---------------------------------------------------------------------------
# Auth middleware (optional, token-based)
# ---------------------------------------------------------------------------

@app.middleware("http")
async def check_auth(request: Request, call_next):
    health_path = f"{APP_PREFIX}/health"
    root_path = APP_PREFIX or "/"
    static_path = f"{APP_PREFIX}/static"
    if ADMIN_TOKEN and request.url.path not in (health_path,):
        token = request.headers.get("X-Admin-Token") or request.query_params.get("token")
        if request.method == "GET" and request.url.path in (root_path, static_path):
            pass  # allow page load, auth checked via JS for mutations
        elif request.method != "GET" and token != ADMIN_TOKEN:
            return JSONResponse({"error": "unauthorized"}, status_code=401)
    return await call_next(request)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get(f"{APP_PREFIX}/", response_class=HTMLResponse)
@app.get(f"{APP_PREFIX}", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {
        "request": request,
        "domain": DOMAIN,
        "bucket": S3_BUCKET,
        "prefix": APP_PREFIX,
    })


@app.get(f"{APP_PREFIX}/health")
async def health():
    return {"status": "ok"}


@app.get(f"{APP_PREFIX}/api/apps")
async def api_list_apps():
    return {"apps": list_apps()}


@app.post(f"{APP_PREFIX}/api/apps/{{app_name}}/deploy")
async def api_deploy(app_name: str, file: UploadFile = File(...), clean: bool = Form(False)):
    """Deploy a zip file as an app. Optionally clean existing files first."""
    if not app_name or "/" in app_name or app_name.startswith("."):
        raise HTTPException(400, "Invalid app name")

    content = await file.read()

    # Accept zip files
    if not zipfile.is_zipfile(io.BytesIO(content)):
        raise HTTPException(400, "Upload must be a .zip file")

    # Optionally clean existing files
    if clean:
        delete_app_from_s3(app_name)

    # Extract and upload
    uploaded = 0
    skipped = 0
    zf = zipfile.ZipFile(io.BytesIO(content))

    # Detect if zip has a single root folder (common with downloaded repos)
    names = [n for n in zf.namelist() if not n.endswith("/")]
    common_prefix = ""
    if names:
        parts = [n.split("/") for n in names]
        if len(parts[0]) > 1 and all(p[0] == parts[0][0] for p in parts):
            common_prefix = parts[0][0] + "/"

    for info in zf.infolist():
        if info.is_dir():
            continue
        filename = info.filename

        # Strip common prefix (unwrap single root folder)
        if common_prefix and filename.startswith(common_prefix):
            filename = filename[len(common_prefix):]

        # Skip hidden files and OS junk
        if any(part.startswith(".") for part in filename.split("/")):
            skipped += 1
            continue
        if filename.startswith("__MACOSX"):
            skipped += 1
            continue

        if not filename:
            continue

        s3_key = f"{app_name}/{filename}"
        data = zf.read(info.filename)

        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=data,
            ContentType=guess_content_type(filename),
            CacheControl=cache_control_for(filename),
        )
        uploaded += 1

    # Invalidate CloudFront
    invalidate_cache(app_name)

    return {
        "app": app_name,
        "uploaded": uploaded,
        "skipped": skipped,
        "url": f"https://{DOMAIN}/{app_name}/",
    }


@app.delete(f"{APP_PREFIX}/api/apps/{{app_name}}")
async def api_delete_app(app_name: str):
    if not app_name or "/" in app_name or app_name.startswith("."):
        raise HTTPException(400, "Invalid app name")

    deleted = delete_app_from_s3(app_name)
    if deleted == 0:
        raise HTTPException(404, f"App '{app_name}' not found")

    invalidate_cache(app_name)
    return {"app": app_name, "deleted_files": deleted}


@app.post(f"{APP_PREFIX}/api/apps/{{app_name}}/invalidate")
async def api_invalidate(app_name: str):
    if not cf or not CF_DISTRIBUTION_ID:
        raise HTTPException(400, "CloudFront not configured")
    invalidate_cache(app_name)
    return {"app": app_name, "status": "invalidation_created"}
