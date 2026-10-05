"""AWS Lambda handler for the daily GeoNames update.

EventBridge Scheduler calls the function once a day. A manual call may
pass {"date": "YYYY-MM-DD"} to process a specific day.
"""

import logging
import os

import boto3

from geonames_sync import parse_day, run

logging.getLogger().setLevel(logging.INFO)
s3 = boto3.client("s3")
BUCKET = os.environ["DATA_BUCKET"]


def store(key: str, data: bytes) -> None:
    s3.put_object(Bucket=BUCKET, Key=key, Body=data)


def lambda_handler(event, context):
    day = parse_day(event.get("date")) if isinstance(event, dict) else None
    return run(store, day)
