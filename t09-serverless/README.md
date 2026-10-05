# T09 – Täglicher GeoNames-Abgleich als Function

**Ziel:** Eine AWS-Lambda-Function lädt jeden Morgen die Änderungs- und Löschdateien des Vortags von GeoNames, filtert sie auf die Orte von `cities15000` und legt sie in S3 ab. Ist `database_url` gesetzt, spielt sie die Änderungen zusätzlich in die Tabelle `places` ein. Gestartet wird sie von EventBridge Scheduler.

**Kosten:** Im Free Tier (1 Million Aufrufe und 400.000 GB-Sekunden pro Monat für Lambda, 14 Millionen Aufrufe für EventBridge Scheduler). Ein Lauf dauert wenige Sekunden.

## Aufbau

| Datei | Inhalt |
|---|---|
| `function/geonames_sync.py` | anbieterneutraler Kern: Download, Filter, Speichern, optional Datenbank (identisch in allen drei Repositories) |
| `function/handler.py` | Lambda-Handler: schreibt mit boto3 nach S3 |
| `package.sh` | baut `build/` mit Code und Abhängigkeit `pg8000` |
| `infra/main.tf` | Bucket, Rollen, Lambda, Log-Gruppe (7 Tage), Zeitplan |
| `invoke.sh` | Function von Hand aufrufen, Log und Ergebnis anzeigen |

## Lokal testen

```bash
cd function
python3 geonames_sync.py --date 2026-10-01 --out ../out
```

Ohne Cloud: Die Dateien landen unter `out/geonames/changes/<datum>/`. Mit der AWS SAM CLI lässt sich der Handler auch im Lambda-Container ausführen (`sam local invoke`); dafür ist eine SAM-Vorlage nötig, die hier bewusst fehlt – der Kurs nutzt OpenTofu.

## Ausrollen

```bash
./package.sh
cd ..
tools/tofu.sh t09-serverless/infra apply
t09-serverless/invoke.sh                 # gestern
t09-serverless/invoke.sh 2026-10-01      # bestimmter Tag
aws s3 ls --recursive s3://$(tools/tofu.sh t09-serverless/infra output -raw bucket)
```

Mit Datenbank (z. B. aus Termin 6 oder `t08-iac` mit `enable_database=true`):

```bash
tools/tofu.sh t09-serverless/infra apply -var "database_url=postgresql://…?sslmode=require"
```

Damit die Function die Datenbank erreicht, muss deren Firewall den Zugriff erlauben. Lambda hat ohne VPC-Anbindung keine feste Absenderadresse; für die Übung genügt es, die Security Group vorübergehend zu öffnen. Sauberer ist eine Lambda in der VPC der Datenbank – dann braucht sie für den Download aber ein NAT-Gateway.

## Prüfen

- Ein zweiter Aufruf für denselben Tag ändert nichts (Idempotenz): gleiche Dateien, Upsert statt doppelter Zeilen.
- `aws logs tail /aws/lambda/pf-<owner>-t09-geonames-sync --since 1h`
- Kaltstart: Die erste Ausführung nach einer Pause zeigt im Log `Init Duration`.

## Aufräumen

```bash
tools/tofu.sh t09-serverless/infra destroy
```

## Optional: ereignisgesteuert

Eine zweite Function könnte auf neue Objekte im Bucket reagieren (S3-Ereignis → Lambda), etwa einen neuen OSM-Auszug unter `osm/` zu POIs verarbeiten. In OpenTofu: `aws_s3_bucket_notification` und `aws_lambda_permission`. Achtung bei Ereignissen auf demselben Bucket, in den die Function schreibt: Präfixe trennen, sonst entsteht eine Endlosschleife.

## Fragen zum Weiterdenken

- Was passiert, wenn GeoNames die Datei um 6:30 Uhr noch nicht veröffentlicht hat? Wie helfen Retries und eine Dead-Letter-Queue?
- Warum muss die Function idempotent sein, obwohl sie nur einmal am Tag läuft?
- Ab wie vielen Aufrufen wäre ein dauerhaft laufender Container günstiger?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Function | Lambda | Azure Functions (Flex Consumption) | Cloud Run functions |
| Zeitsteuerung | EventBridge Scheduler | Timer-Trigger im Code | Cloud Scheduler |
| Lokale Entwicklung | SAM CLI | Functions Core Tools, Azurite | Functions Framework |
