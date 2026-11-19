# 08 – Analysen im Data Lake: GeoParquet, DuckDB und Athena

**Ziel:** Die Orte von PlaceFinder liegen als GeoParquet im S3-Bucket von `base`. DuckDB auf dem eigenen Rechner fragt die Datei direkt im Bucket ab, ohne Server und ohne die ganze Datei herunterzuladen. Zusatz: dieselben Abfragen serverlos mit Amazon Athena.

**Baut auf:** [06-infrastructure-as-code](../06-infrastructure-as-code/README.md) (`base` mit dem Bucket); lokal [cloud-labs-local/10-analytics](https://github.com/mf-iu/cloud-labs-local/tree/master/10-analytics) · **Termin:** 10

**Kosten:** praktisch keine. Die Datei hat rund 1,5 MB; Speicher, Anfragen und der Datentransfer zum eigenen Rechner bleiben im Freikontingent. Zusatz Athena: 5 USD je TB gelesener Daten, mindestens 10 MB je Abfrage – eine Abfrage auf `places.parquet` kostet rund 0,00005 USD. Die Workgroup bricht jede Abfrage ab, die mehr als 1 GB lesen würde.

| Datei | Aufgabe |
|---|---|
| `upload.sh` | `cities15000` mit `export_geoparquet.py` aus `cloud-labs-local` in GeoParquet umwandeln und nach `s3://<bucket von base>/places/` laden |
| `query-duckdb.sh` | `query_duckdb.py` aus `cloud-labs-local` auf die Datei im Bucket anwenden, mit den Zugangsdaten der CLI-Anmeldung |
| `infra/` | Zusatz: Athena-Workgroup mit Kostenlimit, eigener Bucket für die Ergebnisse, Tabelle im Glue Data Catalog |
| `athena.sh` | Zusatz: eine SQL-Abfrage mit Athena ausführen und die gelesene Datenmenge zeigen |

## Voraussetzungen

- `base` steht: `tools/tofu.sh 06-infrastructure-as-code/base output bucket` zeigt den Bucket.
- Die lokalen Schritte 1 und 2 aus `cloud-labs-local/10-analytics` sind bekannt (GeoParquet erzeugen und lokal abfragen).
- `aws login` ist aktiv; `01-account/check-cli.sh` prüft das.

## Übung im Termin

```bash
cd /workspaces/cloud-labs-aws
08-analytics/upload.sh                     # cities15000 -> places.parquet -> s3://…/places/
08-analytics/query-duckdb.sh               # dieselben Abfragen wie lokal, jetzt auf den Bucket
08-analytics/query-duckdb.sh --explain     # was wird gelesen?
tools/find-leftovers.sh                    # nur noch base
```

`upload.sh` liest den Namen des Buckets aus den Ausgaben von `base` (`base_output bucket` in `lib/provider.sh`), erzeugt `places.parquet` in `cloud-labs-local/.state/data/` und lädt die Datei mit `aws s3 cp` hoch.

`query-duckdb.sh` holt mit `aws configure export-credentials` temporäre Schlüssel der eigenen Anmeldung und übergibt sie DuckDB als Secret, beschränkt auf diesen Bucket (`SCOPE 's3://<bucket>'`). Das Secret steht in der Umgebungsvariablen `DUCKDB_SECRET`; so taucht es weder in der Befehlszeile noch in `ps` auf. Dann ruft das Skript `cloud-labs-local/10-analytics/query_duckdb.py` mit der Adresse `s3://<bucket>/places/places.parquet` auf. Weitere Argumente gehen an das Python-Skript.

DuckDB liest die Datei mit Range Requests über HTTPS: zuerst den Footer am Ende, dann nur die Column Chunks der gefragten Spalten. `--explain` zeigt das im Plan: `Projections` (gelesene Spalten), `Filters` (Filter beim Lesen), `Row Groups Scanned` und im Abschnitt *HTTPFS HTTP Stats* die Zahl der Anfragen und die übertragenen Bytes – für die Abfrage auf Deutschland rund 0,4 von 1,5 MB. Die Datei hat nur eine Row Group; gespart wird hier an den Spalten. Wie das Überspringen von Row Groups wirkt, zeigt der Zusatz in `cloud-labs-local/10-analytics`.

Die Datei bleibt bis zum Kursende im Bucket von `base` und kann im Abschlussprojekt weiterverwendet werden. Zu löschen gibt es nach der Übung nichts.

## Zusatz: serverlos mit Athena

```bash
tools/tofu.sh 08-analytics/infra apply     # Workgroup, Ergebnis-Bucket, Glue-Datenbank und -Tabelle
08-analytics/athena.sh                     # Beispielabfrage: größter Ort je Land
08-analytics/athena.sh "SELECT name, population FROM places WHERE country_code = 'DE' ORDER BY population DESC LIMIT 5"
tools/tofu.sh 08-analytics/infra destroy
```

Athena ist eine serverlose SQL-Engine (Trino): Es gibt nichts zu starten, bezahlt wird je gelesener Datenmenge. Die Tabelle `places` im Glue Data Catalog beschreibt nur Ort und Spalten der Dateien unter `s3://<bucket von base>/places/` (Schema on Read); die Daten bleiben im Bucket. Die Geometriespalte `geom` fehlt in der Tabelle: Breite und Länge stehen als normale Zahlen in der Datei. `athena.sh` startet die Abfrage, fragt alle zwei Sekunden nach dem Stand, zeigt das Ergebnis und die gelesene Datenmenge (`DataScannedInBytes`).

| Datei | Inhalt |
|---|---|
| `infra/base.tf` | liest den Bucket aus dem State von `base` (`terraform_remote_state`) |
| `infra/main.tf` | Bucket für die Ergebnisse (Ablauf nach einem Tag), Workgroup mit Limit von 1 GB je Abfrage, Glue-Datenbank, Tabelle `places` |
| `infra/outputs.tf` | Namen von Workgroup und Datenbank für `athena.sh` |

Ausprobieren: `athena.sh "SELECT count(*) FROM places"` und `athena.sh "SELECT * FROM places LIMIT 10"` – wie unterscheidet sich die gelesene Datenmenge? Abgerechnet werden trotzdem mindestens 10 MB.

## Zusatz: Overture Maps

Overture Maps liegt im öffentlichen Bucket `s3://overturemaps-us-west-2`. DuckDB liest ihn ohne Anmeldung, der Datentransfer kostet das eigene Konto nichts:

```bash
uv run ../cloud-labs-local/10-analytics/overture.py <release>   # aktuelle Kennung: docs.overturemaps.org/release/latest
```

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No output bucket from base` | `base` fehlt oder ist abgebaut. | `tools/tofu.sh 06-infrastructure-as-code/base apply` |
| `HTTP 403` in DuckDB | Die Anmeldung ist abgelaufen. | `aws login --remote`, dann erneut starten |
| `HTTP 404` in DuckDB | `upload.sh` lief noch nicht. | `08-analytics/upload.sh` |
| `Failed to download extension` | DuckDB lädt `httpfs` und `h3` beim ersten Gebrauch. | Netz prüfen, erneut starten |
| Athena: `Query FAILED … bytes scanned limit` | Die Abfrage würde mehr als 1 GB lesen. | Abfrage einschränken; das Limit ist Absicht |
| Athena: `HIVE_BAD_DATA` | Eine andere Datei mit anderem Schema liegt unter `places/`. | nur `places.parquet` dort ablegen |

## Aufräumen

Nach der Übung nichts; `places.parquet` bleibt im Bucket von `base`. Nach dem Zusatz:

```bash
tools/tofu.sh 08-analytics/infra destroy
tools/find-leftovers.sh
```

## Fragen zum Weiterdenken

- DuckDB auf dem eigenen Rechner oder Athena: Wer bezahlt was, und wo laufen die Daten durch?
- Warum ist Parquet für Athena billiger als CSV, obwohl die Daten dieselben sind?
- Was bedeutet „Schema on Read“ für Fehler in den Daten? Was passiert, wenn jemand eine Datei mit anderem Schema nach `places/` lädt?
- Wann reicht DuckDB auf einem Rechner, und wann braucht man Athena, Redshift oder Spark (EMR)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Data Lake | S3 | Blob Storage, Data Lake Storage | Cloud Storage |
| DuckDB liest mit | temporären Schlüsseln der Anmeldung | Verbindungszeichenkette des Speicherkontos | OAuth-Token der Anmeldung über HTTPS |
| Serverloses SQL | Athena | Fabric, Synapse serverless SQL | BigQuery |
| Overture Maps | S3 (us-west-2) | Blob Storage (West US 2) | BigQuery Public Datasets |
