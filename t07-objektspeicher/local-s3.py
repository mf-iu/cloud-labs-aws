# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3>=1.40"]
# ///
"""S3 client for the local object storage: SeaweedFS, service seaweedfs in
compose.yaml of PlaceFinder (from tag t07). Every S3-compatible store works
the same way; the endpoint and the keys come from the environment.

Usage: uv run local-s3.py <command>   (--help for details)
  setup                  CORS for the map and a lifecycle rule for raw/
  upload FILE [KEY]      upload a file; default key raw/<name>, tiles/ for .pmtiles
  list                   objects in the bucket
  presign KEY [SECONDS]  pre-signed URL (default 3600 s), tested without
                         signature, with a range request and with CORS
  map KEY [SECONDS]      address of the PlaceFinder map with ?tiles=<pre-signed
                         URL> (default 86400 s)

Environment (defaults as in compose.yaml): S3_ENDPOINT=http://localhost:8333,
S3_BUCKET=placefinder, LOCAL_S3_ACCESS_KEY=placefinder,
LOCAL_S3_SECRET_KEY=placefinder-local. The keys are passed explicitly, so
the credentials of a cloud provider in ~/.aws are never used here.
"""

import argparse
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.message import Message
from pathlib import Path

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError, EndpointConnectionError

ENDPOINT = os.environ.get("S3_ENDPOINT", "http://localhost:8333")
BUCKET = os.environ.get("S3_BUCKET", "placefinder")
MAP_ORIGIN = "http://localhost:5173"  # frontend/index.html of PlaceFinder

CORS = {
    "CORSRules": [
        {
            # the map reads PMTiles with range requests and needs ETag and
            # Content-Range in the answer
            "AllowedOrigins": [MAP_ORIGIN],
            "AllowedMethods": ["GET", "HEAD"],
            "AllowedHeaders": ["Range"],
            "ExposeHeaders": ["ETag", "Content-Length", "Content-Range"],
            "MaxAgeSeconds": 3600,
        }
    ]
}
LIFECYCLE = {
    "Rules": [
        {
            "ID": "expire-raw-data",
            "Status": "Enabled",
            "Filter": {"Prefix": "raw/"},
            "Expiration": {"Days": 30},
        }
    ]
}


def client():
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        aws_access_key_id=os.environ.get("LOCAL_S3_ACCESS_KEY", "placefinder"),
        aws_secret_access_key=os.environ.get("LOCAL_S3_SECRET_KEY", "placefinder-local"),
        region_name="us-east-1",  # signed into every request; SeaweedFS accepts any
        config=Config(
            s3={"addressing_style": "path"},  # localhost:8333/<bucket>/<key>
            signature_version="s3v4",
            request_checksum_calculation="when_required",  # plain uploads
        ),
    )


def http(url: str, method: str = "GET", headers: dict | None = None) -> tuple[int, Message]:
    """Status and headers of a request; errors are answers, too."""
    request = urllib.request.Request(url, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.headers


def presign(s3, key: str, seconds: int) -> str:
    return s3.generate_presigned_url(
        "get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=seconds
    )


def cmd_setup(s3) -> None:
    s3.put_bucket_cors(Bucket=BUCKET, CORSConfiguration=CORS)
    s3.put_bucket_lifecycle_configuration(Bucket=BUCKET, LifecycleConfiguration=LIFECYCLE)
    rule = s3.get_bucket_cors(Bucket=BUCKET)["CORSRules"][0]
    print(f"Bucket {BUCKET} at {ENDPOINT}")
    print(f"  CORS: {rule['AllowedMethods']} from {rule['AllowedOrigins']}, "
          f"headers {rule['AllowedHeaders']}, exposes {rule['ExposeHeaders']}")
    print("  Lifecycle: objects under raw/ expire after 30 days")


def cmd_upload(s3, file: str, key: str | None = None) -> None:
    path = Path(file)
    if not path.is_file():
        sys.exit(f"File not found: {file}")
    key = key or ("tiles/" if path.suffix == ".pmtiles" else "raw/") + path.name
    s3.upload_file(str(path), BUCKET, key)  # in parts of 8 MB for large files
    print(f"Uploaded {path.stat().st_size:,} bytes to s3://{BUCKET}/{key}")


def cmd_list(s3) -> None:
    for obj in s3.list_objects_v2(Bucket=BUCKET).get("Contents", []):
        print(f"{obj['LastModified']:%Y-%m-%d %H:%M}  {obj['Size']:>12,}  {obj['Key']}")


def cmd_presign(s3, key: str, seconds: str = "3600") -> None:
    url = presign(s3, key, int(seconds))
    print(f"Pre-signed URL ({seconds} s):\n{url}\n")
    status, _ = http(f"{ENDPOINT}/{BUCKET}/{urllib.parse.quote(key)}")
    print(f"Without signature:          {status}  (expected 403: the bucket is private)")
    status, headers = http(url, headers={"Range": "bytes=0-99"})
    print(f"Range bytes=0-99:           {status}  {headers.get('Content-Range', '')}"
          "  (expected 206 Partial Content)")
    status, headers = http(url, "OPTIONS", {
        "Origin": MAP_ORIGIN, "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "range"})
    print(f"CORS preflight from {MAP_ORIGIN}: {status}  "
          f"Access-Control-Allow-Origin: {headers.get('Access-Control-Allow-Origin', '-')}")


def cmd_map(s3, key: str, seconds: str = "86400") -> None:
    url = presign(s3, key, int(seconds))
    print(f"Map with the tiles of s3://{BUCKET}/{key} (valid for {seconds} s):")
    print(f"{MAP_ORIGIN}/?tiles={urllib.parse.quote(url, safe='')}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="S3 client for the local object storage (SeaweedFS)")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="CORS for the map, lifecycle rule for raw/")
    upload = commands.add_parser("upload", help="upload a file")
    upload.add_argument("file")
    upload.add_argument("key", nargs="?", help="default raw/<name>, tiles/<name> for .pmtiles")
    commands.add_parser("list", help="objects in the bucket")
    for name, seconds, text in (("presign", "3600", "pre-signed URL, tested"),
                                ("map", "86400", "address of the map with ?tiles=")):
        command = commands.add_parser(name, help=text)
        command.add_argument("key")
        command.add_argument("seconds", nargs="?", default=seconds, help=f"default {seconds}")
    args = vars(parser.parse_args())
    command = globals()["cmd_" + args.pop("command")]
    try:
        command(client(), **args)
    except EndpointConnectionError:
        sys.exit(f"No answer from {ENDPOINT}. Start SeaweedFS: "
                 "docker compose up --detach seaweedfs (in /workspaces/placefinder)")
    except ClientError as error:
        sys.exit(f"S3 error: {error}")


if __name__ == "__main__":
    main()
