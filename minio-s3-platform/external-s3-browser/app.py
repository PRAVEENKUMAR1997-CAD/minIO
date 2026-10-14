import os
import re
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
MINIO_REGION = os.getenv("MINIO_REGION", "us-east-1")
MINIO_SECURE = MINIO_ENDPOINT.startswith("https://")

APPROVED_BUCKETS = {
    name.strip()
    for name in os.environ["APPROVED_S3_BUCKETS"].split(",")
    if name.strip()
}

_INVALID_CRED_CODES = {
    "InvalidAccessKeyId",
    "SignatureDoesNotMatch",
    "InvalidClientTokenId",
    "AuthFailure",
    "ExpiredToken",
}

_DENIED_CODES = {
    "AccessDenied",
    "Forbidden",
    "NoSuchBucket",
    "NotFound",
    "AllAccessDisabled",
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


def _error_code(exc):
    if isinstance(exc, ClientError):
        return ((exc.response.get("Error") or {}).get("Code") or "").strip()
    return ""


def resolve_allowed_buckets(client):
    """Return (allowed_buckets, credentials_valid) using MinIO policies.

    Each approved AWS bucket is allowed only if the same-named MinIO bucket
    accepts HeadBucket for this user. Invalid credentials fail closed.
    """
    allowed = []
    credentials_valid = False
    for bucket in sorted(APPROVED_BUCKETS):
        try:
            client.head_bucket(Bucket=bucket)
        except ClientError as exc:
            code = _error_code(exc)
            if code in _INVALID_CRED_CODES:
                return [], False
            status = (exc.response.get("ResponseMetadata") or {}).get("HTTPStatusCode")
            if code in _DENIED_CODES or status == 403:
                credentials_valid = True
            continue
        except (BotoCoreError, ValueError):
            return [], False
        allowed.append(bucket)
        credentials_valid = True
    return allowed, credentials_valid


def session_allowed_buckets():
    stored = session.get("allowed_buckets") or []
    return {name for name in stored if name in APPROVED_BUCKETS}


def require_allowed_bucket(bucket):
    if bucket not in session_allowed_buckets():
        abort(404)

_S3_STATUS = {
    "AccessDenied": 403,
    "Forbidden": 403,
    "InvalidAccessKeyId": 403,
    "SignatureDoesNotMatch": 403,
    "NoSuchBucket": 404,
    "NoSuchKey": 404,
    "NotFound": 404,
}

_ARN_RE = re.compile(r"arn:aws:[^\s\"']+", re.IGNORECASE)


def sanitize_aws_message(message):
    """Strip AWS ARNs so identity details are not shown in the UI."""
    if not message:
        return ""
    text = _ARN_RE.sub("", message)
    text = text.replace('""', "").replace("''", "")
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"\s+([:,.])", r"\1", text)
    text = re.sub(r"User:\s+is", "User is", text, flags=re.IGNORECASE)
    text = re.sub(
        r"on resource:\s+because",
        "on this resource because",
        text,
        flags=re.IGNORECASE,
    )
    return text.strip(' :.-"')


def s3_error_parts(exc):
    """Return HTTP status, upstream message, and error code for an S3 failure."""
    if isinstance(exc, ClientError):
        error = exc.response.get("Error") or {}
        message = (error.get("Message") or "").strip() or "Unable to access S3."
        code = (error.get("Code") or "").strip()
        status = (exc.response.get("ResponseMetadata") or {}).get("HTTPStatusCode")
        if not isinstance(status, int) or not 400 <= status <= 599:
            status = _S3_STATUS.get(code, 502)
        return status, sanitize_aws_message(message), code
    detail = sanitize_aws_message(str(exc).strip())
    return 502, detail or "Unable to access S3.", ""

def error_page(status_code, message, error_code=""):
    return render_template(
        "error.html",
        status_code=status_code,
        message=sanitize_aws_message(message),
        error_code=error_code,
    ), status_code

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
            allowed, credentials_valid = resolve_allowed_buckets(client)
        except (ClientError, BotoCoreError, ValueError):
            allowed, credentials_valid = [], False

        if not credentials_valid:
            flash("Login failed. Check your MinIO access key and secret key.")
            return render_template("login.html"), 401

        session.clear()
        session["authenticated"] = True
        session["minio_user"] = access_key
        session["allowed_buckets"] = allowed
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
    return render_template("buckets.html", buckets=sorted(session_allowed_buckets()))

@app.route("/bucket/<bucket>")
def browse(bucket):
    result = require_login()
    if result:
        return result
    require_allowed_bucket(bucket)

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
    except (ClientError, BotoCoreError) as exc:
        status, message, code = s3_error_parts(exc)
        return error_page(status, message, code)

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
    require_allowed_bucket(bucket)

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

@app.errorhandler(400)
@app.errorhandler(403)
@app.errorhandler(404)
@app.errorhandler(502)
def http_error(error):
    return error_page(error.code, error.description or "Request failed.")

if not APPROVED_BUCKETS:
    raise RuntimeError("APPROVED_S3_BUCKETS must contain at least one bucket.")
