# /// script
# requires-python = ">=3.12"
# dependencies = ["duckdb>=1.4"]
# ///
"""Query GeoParquet in S3 with DuckDB: own data and Overture Maps places.

AWS credentials come from the environment (see query-duckdb.sh).
Usage: uv run query_duckdb.py <bucket> [overture release]
"""

import os
import sys

import duckdb

ERFURT = {"xmin": 10.90, "xmax": 11.20, "ymin": 50.90, "ymax": 51.10}


def show(con: duckdb.DuckDBPyConnection, title: str, sql: str) -> None:
    print(f"\n--- {title}")
    con.sql(sql).show(max_rows=20)


def main(bucket: str, release: str | None) -> None:
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; INSTALL aws; LOAD aws;")
    region = os.environ.get("AWS_REGION", "eu-central-1")
    # Own bucket: credentials from the environment variables
    con.execute(f"""
        CREATE SECRET lake (TYPE s3, PROVIDER credential_chain, CHAIN 'env',
                            REGION '{region}', SCOPE 's3://{bucket}')
    """)
    places = f"read_parquet('s3://{bucket}/places/*.parquet')"

    show(con, "Largest places in Germany", f"""
        SELECT name, population, round(latitude, 2) AS lat, round(longitude, 2) AS lon
        FROM {places} WHERE country_code = 'DE'
        ORDER BY population DESC LIMIT 10
    """)
    show(con, "Places with at least 15,000 inhabitants per country", f"""
        SELECT country_code, count(*) AS places, sum(population) AS population
        FROM {places} GROUP BY ALL ORDER BY places DESC LIMIT 10
    """)

    # H3: hexagonal grid cells (community extension)
    con.execute("INSTALL h3 FROM community; LOAD h3;")
    show(con, "Places per H3 cell (resolution 3) in Germany", f"""
        SELECT h3_h3_to_string(h3_latlng_to_cell(latitude, longitude, 3)) AS cell,
               count(*) AS places, string_agg(name, ', ') AS names
        FROM {places} WHERE country_code = 'DE'
        GROUP BY cell ORDER BY places DESC LIMIT 5
    """)

    if not release:
        print("\nSet OVERTURE_RELEASE (e.g. 2026-09-17.0) to query Overture Maps.")
        return
    # Overture Maps: public bucket in us-west-2, no credentials needed.
    # Only the row groups whose bbox matches are read (predicate pushdown).
    con.execute("""
        CREATE SECRET overture (TYPE s3, REGION 'us-west-2',
                                SCOPE 's3://overturemaps-us-west-2')
    """)
    overture = (f"read_parquet('s3://overturemaps-us-west-2/release/{release}"
                "/theme=places/type=place/*', hive_partitioning = true)")
    box = ERFURT
    show(con, f"Overture places around Erfurt ({release})", f"""
        SELECT names.primary AS name, round(confidence, 2) AS confidence
        FROM {overture}
        WHERE bbox.xmin BETWEEN {box['xmin']} AND {box['xmax']}
          AND bbox.ymin BETWEEN {box['ymin']} AND {box['ymax']}
        ORDER BY confidence DESC LIMIT 15
    """)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.environ.get("OVERTURE_RELEASE"))
