# /// script
# requires-python = ">=3.12"
# dependencies = ["duckdb>=1.4"]
# ///
"""Convert GeoNames cities15000.txt into a GeoParquet file.

The file gets a WKB geometry column "geom" (GeoParquet 1.0 metadata)
and keeps latitude/longitude as plain columns, so that query engines
without geometry support (e.g. Athena, BigQuery external tables) can
work with it as well.

Usage: uv run export_geoparquet.py <cities15000.txt> <places.parquet>
"""

import sys

import duckdb

COLUMNS = {
    "geonameid": "INTEGER", "name": "VARCHAR", "asciiname": "VARCHAR",
    "alternatenames": "VARCHAR", "latitude": "DOUBLE", "longitude": "DOUBLE",
    "feature_class": "VARCHAR", "feature_code": "VARCHAR", "country_code": "VARCHAR",
    "cc2": "VARCHAR", "admin1_code": "VARCHAR", "admin2_code": "VARCHAR",
    "admin3_code": "VARCHAR", "admin4_code": "VARCHAR", "population": "BIGINT",
    "elevation": "INTEGER", "dem": "INTEGER", "timezone": "VARCHAR",
    "modification_date": "DATE",
}


def main(source: str, target: str) -> None:
    con = duckdb.connect()
    columns = ", ".join(f"'{name}': '{kind}'" for name, kind in COLUMNS.items())
    con.execute(f"""
        CREATE TABLE places AS
        SELECT * FROM read_csv('{source}', delim = '\t', header = false,
                               quote = '', escape = '', columns = {{{columns}}})
    """)
    # GEOMETRY is a core type in DuckDB >= 1.4; it is written as WKB
    # together with GeoParquet metadata. Sorting by country improves
    # the compression and the row-group statistics for filters.
    con.execute(f"""
        COPY (
            SELECT geonameid, name, asciiname, latitude, longitude,
                   feature_code, country_code, admin1_code, population,
                   timezone, modification_date,
                   printf('POINT(%f %f)', longitude, latitude)::GEOMETRY AS geom
            FROM places
            ORDER BY country_code, population DESC
        ) TO '{target}' (FORMAT parquet, COMPRESSION zstd)
    """)
    count = con.execute(f"SELECT count(*) FROM '{target}'").fetchone()[0]
    print(f"wrote {count} places to {target}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
