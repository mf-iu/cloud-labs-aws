# T10 – Data Lake mit GeoParquet, DuckDB und Athena

**Ziel:** GeoNames-Orte liegen als GeoParquet in S3. DuckDB fragt die Datei direkt im Bucket ab, ebenso die öffentlichen Overture-Maps-Daten. Amazon Athena führt dieselben Abfragen serverlos über einen Tabelleneintrag im Glue Data Catalog aus (Schema on Read).

**Kosten:** Speicher praktisch null. Athena: 5 USD je TB gelesener Daten, mindestens 10 MB je Abfrage – eine Abfrage auf `places.parquet` kostet Bruchteile eines Cents. Die Workgroup bricht jede Abfrage ab, die mehr als 1 GB lesen würde. Overture-Abfragen mit DuckDB laufen über das Internet und kosten in AWS nichts.

## Schritte

```bash
cd ..
tools/tofu.sh t10-datenanalyse/infra apply   # Bucket, Athena-Workgroup, Glue-Datenbank und -Tabelle
t10-datenanalyse/upload.sh                    # cities15000 -> GeoParquet -> s3://…/places/
t10-datenanalyse/query-duckdb.sh              # DuckDB auf S3
t10-datenanalyse/athena.sh                    # Athena-Beispielabfrage
t10-datenanalyse/athena.sh "SELECT name, population FROM places WHERE country_code = 'DE' ORDER BY population DESC LIMIT 5"
```

`export_geoparquet.py` schreibt eine Geometriespalte `geom` als WKB mit GeoParquet-Metadaten und behält Breite und Länge als normale Spalten, damit auch Werkzeuge ohne Geometrietyp damit arbeiten können. Die Datei ist nach Land sortiert, sodass Filter auf `country_code` ganze Row Groups überspringen.

### Overture Maps

Overture veröffentlicht etwa monatlich ein Release als GeoParquet im öffentlichen Bucket `s3://overturemaps-us-west-2`. Die aktuelle Release-Kennung steht unter <https://docs.overturemaps.org/release/latest/>:

```bash
t10-datenanalyse/query-duckdb.sh 2026-09-17.0     # Beispielkennung, aktuelle eintragen
```

DuckDB liest dabei nur die Row Groups, deren Bounding Box zum Filter passt (Predicate Pushdown) – von den vielen Gigabyte der weltweiten Orte werden nur wenige Megabyte übertragen.

## Prüfen

- `athena.sh` zeigt am Ende die gelesene Datenmenge. Wie ändert sie sich, wenn nur zwei Spalten abgefragt werden?
- In der Athena-Konsole die Workgroup `pf-<owner>-t10` wählen und die Tabelle `places` ansehen.

## Aufräumen

```bash
tools/tofu.sh t10-datenanalyse/infra destroy
```

## Fragen zum Weiterdenken

- Warum ist Parquet für Analysen schneller und billiger als CSV, obwohl die Daten dieselben sind?
- Wann reicht DuckDB auf einem Rechner, und wann braucht man Athena, Spark oder ein Data Warehouse?
- Was bedeutet „Schema on Read“ für Fehler in den Daten?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Data Lake | S3 | Blob Storage / Data Lake Storage | Cloud Storage |
| Serverlose SQL-Abfragen | Athena | Fabric, Synapse serverless SQL | BigQuery |
| Overture Maps | S3 (us-west-2) | Blob Storage (West US 2) | BigQuery Public Datasets |
