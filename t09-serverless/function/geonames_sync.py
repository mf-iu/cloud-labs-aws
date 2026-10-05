"""Daily GeoNames update for PlaceFinder.

Downloads the change files that GeoNames publishes every day for the
previous day (modifications-YYYY-MM-DD.txt, deletes-YYYY-MM-DD.txt),
keeps the places that belong to the cities15000 subset and

1. stores them as TSV files plus a JSON summary in object storage, and
2. applies them to the PostgreSQL table "places" if DATABASE_URL is set.

The module is provider independent: the function handlers for AWS,
Azure and Google Cloud only pass a function that stores one object.
Running the same day twice gives the same result (idempotent).

Local test without cloud resources:
    python3 geonames_sync.py --date 2026-10-01 --out ./out
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

BASE_URL = "https://download.geonames.org/export/dump"
USER_AGENT = "PlaceFinder-course/1.0 (cloud computing course)"
MIN_POPULATION = int(os.environ.get("MIN_POPULATION", "15000"))

# Column order of the GeoNames dump files and of the table "places"
COLUMNS = [
    "geonameid", "name", "asciiname", "alternatenames", "latitude", "longitude",
    "feature_class", "feature_code", "country_code", "cc2", "admin1_code",
    "admin2_code", "admin3_code", "admin4_code", "population", "elevation",
    "dem", "timezone", "modification_date",
]
INT_COLUMNS = {"geonameid", "population", "elevation", "dem"}
FLOAT_COLUMNS = {"latitude", "longitude"}

Store = Callable[[str, bytes], None]

log = logging.getLogger("geonames_sync")


@dataclass
class ChangeSet:
    """Changes of one day, filtered to the cities15000 subset."""

    day: dt.date
    modifications: list[list[str]] = field(default_factory=list)
    deletes: list[list[str]] = field(default_factory=list)
    skipped: int = 0


def fetch_text(file_name: str) -> str:
    """Download one file from the GeoNames dump directory."""
    request = urllib.request.Request(
        f"{BASE_URL}/{file_name}", headers={"User-Agent": USER_AGENT}
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise RuntimeError(f"{file_name} is not (yet) published") from error
        raise


def is_relevant(row: list[str]) -> bool:
    """Keep populated places (feature class P) of the cities15000 subset."""
    population = int(row[14] or 0)
    return row[6] == "P" and population >= MIN_POPULATION


def load_changes(day: dt.date) -> ChangeSet:
    """Download and filter the change files of one day."""
    changes = ChangeSet(day=day)
    text = fetch_text(f"modifications-{day:%Y-%m-%d}.txt")
    for line in text.splitlines():
        row = line.split("\t")
        if len(row) != len(COLUMNS):
            continue
        if is_relevant(row):
            changes.modifications.append(row)
        else:
            changes.skipped += 1
    # Deletes have three columns: geonameid, name, comment
    text = fetch_text(f"deletes-{day:%Y-%m-%d}.txt")
    changes.deletes = [line.split("\t") for line in text.splitlines() if line]
    return changes


def to_tsv(rows: list[list[str]]) -> bytes:
    return "".join("\t".join(row) + "\n" for row in rows).encode("utf-8")


def summary(changes: ChangeSet, applied: bool) -> dict:
    return {
        "date": changes.day.isoformat(),
        "modifications": len(changes.modifications),
        "deletes": len(changes.deletes),
        "skipped_other_places": changes.skipped,
        "applied_to_database": applied,
    }


def convert(column: str, value: str) -> object:
    """Convert a field of the dump file to the type of the table column."""
    if value == "":
        return None
    if column in INT_COLUMNS:
        return int(value)
    if column in FLOAT_COLUMNS:
        return float(value)
    return value


def connect(database_url: str):
    """Connect with pg8000; sslmode=require encrypts without verifying."""
    import pg8000.native  # imported here: only needed with a database

    url = urllib.parse.urlparse(database_url)
    params = urllib.parse.parse_qs(url.query)
    ssl_context = None
    if params.get("sslmode", ["require"])[0] != "disable":
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
    return pg8000.native.Connection(
        user=urllib.parse.unquote(url.username or "postgres"),
        password=urllib.parse.unquote(url.password or ""),
        host=url.hostname or "localhost",
        port=url.port or 5432,
        database=(url.path or "/postgres").lstrip("/"),
        ssl_context=ssl_context,
    )


def apply_to_database(changes: ChangeSet, database_url: str) -> None:
    """Upsert modified places and delete removed ones in one transaction."""
    placeholders = ", ".join(f":{c}" for c in COLUMNS)
    updates = ", ".join(f"{c} = EXCLUDED.{c}" for c in COLUMNS[1:])
    upsert = (
        f"INSERT INTO places ({', '.join(COLUMNS)}, geom) "
        f"VALUES ({placeholders}, "
        "ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography) "
        f"ON CONFLICT (geonameid) DO UPDATE SET {updates}, geom = EXCLUDED.geom"
    )
    con = connect(database_url)
    try:
        con.run("START TRANSACTION")
        for row in changes.modifications:
            values = {c: convert(c, v) for c, v in zip(COLUMNS, row, strict=True)}
            con.run(upsert, **values)
        for row in changes.deletes:
            con.run("DELETE FROM places WHERE geonameid = :id", id=int(row[0]))
        con.run("COMMIT")
    except Exception:
        con.run("ROLLBACK")
        raise
    finally:
        con.close()


def run(store: Store, day: dt.date | None = None) -> dict:
    """Process the changes of one day (default: yesterday, UTC)."""
    day = day or dt.datetime.now(dt.timezone.utc).date() - dt.timedelta(days=1)
    changes = load_changes(day)
    prefix = f"geonames/changes/{day:%Y-%m-%d}"
    store(f"{prefix}/modifications.tsv", to_tsv(changes.modifications))
    store(f"{prefix}/deletes.tsv", to_tsv(changes.deletes))

    database_url = os.environ.get("DATABASE_URL", "")
    if database_url:
        apply_to_database(changes, database_url)
    result = summary(changes, applied=bool(database_url))
    store(f"{prefix}/summary.json", json.dumps(result, indent=2).encode("utf-8"))
    log.info("GeoNames sync finished: %s", result)
    return result


def parse_day(value: str | None) -> dt.date | None:
    return dt.date.fromisoformat(value) if value else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--date", help="day to process, YYYY-MM-DD (default: yesterday)")
    parser.add_argument("--out", default="out", help="local directory instead of a bucket")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    def store_local(key: str, data: bytes) -> None:
        path = Path(args.out) / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(f"wrote {path} ({len(data)} bytes)")

    print(json.dumps(run(store_local, parse_day(args.date)), indent=2))


if __name__ == "__main__":
    main()
