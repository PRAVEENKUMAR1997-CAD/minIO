import os
from urllib.parse import quote

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from flask import (
    Flask, abort, flash, redirect, render_template,
    request, Response, session, url_for
)
from flask_wtf.csrf import CSRFProtect

app = Flask(__name__)
app.secret_key = os.environ["APP_SECRET_KEY"]
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.getenv("COOKIE_SECURE", "false").lower() == "true",
    MAX_CONTENT_LENGTH=16 * 1024,
)

CSRFProtect(app)


@app.template_filter('filesizeformat')
def filesizeformat(value):
    """Format file size in human-readable form."""
    try:
        value = int(value)
    except (TypeError, ValueError):
        return '—'
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(value) < 1024.0:
            return f"{value:,.1f} {unit}" if unit != 'B' else f"{value:,} {unit}"
        value /= 1024.0
    return f"{value:,.1f} PB"


MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
MINIO_AUTH_BUCKET = os.environ["MINIO_AUTH_BUCKET"]
MINIO_REGION = os.getenv("MINIO_REGION", "us-east-1")
MINIO_SECURE = MINIO_ENDPOINT.startswith("https://")

APPROVED_BUCKETS = {
    name.strip()
    for name in os.environ["APPROVED_S3_BUCKETS"].split(",")
    if name.strip()
}

def minio_client(access_key, secret_key):
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name=MINIO_REGION,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
            connect_timeout=3,
            read_timeout=5,
            retries={"max_attempts": 1},
        ),
        verify=MINIO_SECURE,
    )

def aws_client():
    # Server-side credentials only (env vars, instance role, or shared config).
    # Users never receive AWS keys.
    return boto3.client(
        "s3",
        region_name=os.getenv("AWS_REGION", "ap-south-1"),
        config=Config(
            connect_timeout=5,
            read_timeout=60,
            retries={"max_attempts": 2},
        ),
    )

def require_login():
    if not session.get("authenticated"):
        return redirect(url_for("login"))
    return None

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        access_key = request.form.get("access_key", "").strip()
        secret_key = request.form.get("secret_key", "")

        if not access_key or not secret_key:
            flash("Enter your MinIO access key and secret key.")
            return render_template("login.html"), 400

        try:
            client = minio_client(access_key, secret_key)
            client.list_objects_v2(
                Bucket=MINIO_AUTH_BUCKET,
                MaxKeys=1,
            )
        except (ClientError, BotoCoreError, ValueError):
            flash("Login failed or the account cannot access the validation bucket.")
            return render_template("login.html"), 401

        session.clear()
        session["authenticated"] = True
        session["minio_user"] = access_key
        return redirect(url_for("index"))

    return render_template("login.html")

@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/")
def index():
    result = require_login()
    if result:
        return result
    return render_template("buckets.html", buckets=sorted(APPROVED_BUCKETS))

@app.route("/bucket/<bucket>")
def browse(bucket):
    result = require_login()
    if result:
        return result
    if bucket not in APPROVED_BUCKETS:
        abort(404)

    prefix = request.args.get("prefix", "")
    if prefix.startswith("/") or ".." in prefix.split("/"):
        abort(400)

    try:
        response = aws_client().list_objects_v2(
            Bucket=bucket,
            Prefix=prefix,
            Delimiter="/",
            MaxKeys=1000,
        )
    except ClientError:
        abort(502)

    folders = response.get("CommonPrefixes", [])
    objects = [
        obj for obj in response.get("Contents", [])
        if obj["Key"] != prefix
    ]

    parent = prefix.rstrip("/").rsplit("/", 1)[0] + "/" if "/" in prefix.rstrip("/") else ""

    return render_template(
        "browse.html",
        bucket=bucket,
        prefix=prefix,
        parent=parent,
        folders=folders,
        objects=objects,
        truncated=response.get("IsTruncated", False),
    )

@app.get("/download/<bucket>")
def download(bucket):
    result = require_login()
    if result:
        return result
    if bucket not in APPROVED_BUCKETS:
        abort(404)

    key = request.args.get("key", "")
    if not key or key.startswith("/") or ".." in key.split("/"):
        abort(400)

    try:
        obj = aws_client().get_object(Bucket=bucket, Key=key)
    except ClientError:
        abort(404)

    filename = key.rsplit("/", 1)[-1]
    disposition = "attachment; filename*=UTF-8''" + quote(filename)

    def stream():
        try:
            for chunk in obj["Body"].iter_chunks(chunk_size=1024 * 1024):
                if chunk:
                    yield chunk
        finally:
            obj["Body"].close()

    return Response(
        stream(),
        headers={
            "Content-Type": "application/octet-stream",
            "Content-Disposition": disposition,
            "Cache-Control": "no-store",
        },
    )

@app.errorhandler(502)
def upstream_error(_error):
    return "Unable to access S3. Check IAM permissions and bucket configuration.", 502

if not APPROVED_BUCKETS:
    raise RuntimeError("APPROVED_S3_BUCKETS must contain at least one bucket.")
