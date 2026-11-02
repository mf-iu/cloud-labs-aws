# 05 – Object Storage und verwaltete Datenbank

In Termin 7 kommen die Rohdaten von GeoNames und die Kacheldatei aus [cloud-labs-local/07-cache-and-storage](https://github.com/mf-iu/cloud-labs-local/tree/master/07-cache-and-storage) in den privaten Object Storage von AWS; die Karte von PlaceFinder liest ihre Kacheln von dort, mit zeitlich begrenztem Zugriff, Range Requests und CORS. Die verwaltete PostgreSQL-Datenbank aus Termin 6 ist **Zusatz** – freiwillig und ohne Folgen für spätere Termine; PostGIS lokal steht in [cloud-labs-local/06-postgis](https://github.com/mf-iu/cloud-labs-local/tree/master/06-postgis).

| Skript | Aufgabe |
|---|---|
| `create-bucket.sh`, `destroy-bucket.sh` | ein privater S3-Bucket beim Anbieter, mit CORS und Lebenszyklusregel; Rohdaten hochladen; alles wieder löschen |
| `upload.sh` | Datei hochladen: `.pmtiles` nach `tiles/`, alles andere nach `raw/` |
| `presign.sh` | Pre-Signed URL für eine Stunde, getestet ohne Signatur, mit Range Request und CORS; für PMTiles die Adresse der Karte |
| `create-db.sh`, `destroy-db.sh` | PostgreSQL 18 beim Anbieter anlegen, nur von der eigenen IP-Adresse erreichbar, und wieder löschen |
| `backups.sh` | automatische Backups und das Zeitfenster für Point-in-Time Recovery anzeigen; ändert nichts |
| `with-db.sh` | ein Skript aus `cloud-labs-local/06-postgis` mit dieser Datenbank ausführen, z. B. `./with-db.sh load-cities.sh` |

**Kosten:** Object Storage: Speicher in Frankfurt ca. 0,025 USD je GB und Monat, dazu Anfragen und ausgehender Verkehr – bei einigen MB praktisch null, aus dem Guthaben. Datenbank: `db.t4g.micro` mit 20 GB gp3 ca. 0,02 USD pro Stunde plus öffentliche IPv4-Adresse, aus dem Guthaben. **Nicht über Nacht laufen lassen.**

## Object Storage mit Kacheln (Termin 7)

Voraussetzung ist die Kacheldatei `erfurt.pmtiles` aus `cloud-labs-local/07-cache-and-storage/make-tiles.sh`; sie liegt in `cloud-labs-local/.state/data/`.

```bash
cd /workspaces/cloud-labs-aws/05-storage
./create-bucket.sh                                             # Bucket mit CORS und Lebenszyklus, cities15000 nach raw/
./upload.sh ../../cloud-labs-local/.state/data/erfurt.pmtiles  # nach tiles/
./presign.sh tiles/erfurt.pmtiles                              # Tests und Adresse der Karte
./presign.sh                                                   # dasselbe für die Rohdaten in raw/geonames/
./destroy-bucket.sh                                            # danach alles löschen
```

Die Adresse der Karte, die `presign.sh` ausgibt, im Browser öffnen, während PlaceFinder und der Webserver für `frontend/` laufen ([cloud-labs-local/07-cache-and-storage](https://github.com/mf-iu/cloud-labs-local/tree/master/07-cache-and-storage)). Die Karte lädt dann ihre Kacheln direkt aus dem Object Storage des Anbieters – ohne eigenen Server dafür.

**Was die Skripte einstellen:**

- Neue Buckets blockieren öffentlichen Zugriff (*Block Public Access*) und verschlüsseln jedes Objekt (SSE-S3); das Skript ändert daran nichts.
- `cors.json`: GET und HEAD von `http://localhost:5173`, Header `Range` erlaubt, `ETag`, `Content-Length` und `Content-Range` für den Browser sichtbar.
- `lifecycle.json`: Objekte unter `raw/` werden nach 30 Tagen gelöscht, unvollständige Multipart-Uploads nach einem Tag.
- `presign.sh` signiert mit den Zugangsdaten der AWS CLI (Signature Version 4). Die URL gilt höchstens so lange wie diese Zugangsdaten – bei kurzlebigen Anmeldungen (SSO) auch kürzer als die angegebene Stunde.

**Prüfen:** Die Ausgabe von `presign.sh` zeigt ohne Signatur `403` – das Objekt ist privat –, mit Signatur und `Range: bytes=0-99` die Antwort `206 Partial Content` mit `Content-Range` und bei der Preflight-Anfrage `Access-Control-Allow-Origin: http://localhost:5173`.

## Zusatz: verwaltete Datenbank (Termin 6)

Freiwillig und ohne Folgen für spätere Termine; die Übung von Termin 6 ist rein lokal ([cloud-labs-local/06-postgis](https://github.com/mf-iu/cloud-labs-local/tree/master/06-postgis)). Pflicht wird die verwaltete Datenbank in Termin 8 – dann im privaten Netz, angelegt mit OpenTofu in `06-infrastructure-as-code/service`. Die Instanz wird stündlich abgerechnet; der Ablauf dauert mit Anlegen und Löschen rund 30 Minuten.

```bash
cd /workspaces/cloud-labs-aws/05-storage
./create-db.sh               # Security Group (5432 nur von der eigenen IP), RDS-Instanz, ca. 10 min
./with-db.sh load-cities.sh  # dieselben Daten, jetzt über das Internet
./with-db.sh query.sh        # Zeiten mit der lokalen Datenbank vergleichen
./with-db.sh test-api.sh     # PlaceFinder lokal, die Daten aus der Cloud
./backups.sh                 # Backups und Point-in-Time Recovery
./destroy-db.sh              # danach löschen – gehört dazu
../tools/find-leftovers.sh   # nichts mehr, was kostet?
```

`with-db.sh` setzt `DATABASE_URL` auf die Datenbank aus `create-db.sh` und ruft das Skript aus [cloud-labs-local/06-postgis](https://github.com/mf-iu/cloud-labs-local/tree/master/06-postgis) auf – dieselben Skripte wie lokal, jetzt über das Internet.

`create-db.sh` erzeugt ein zufälliges Passwort für den Benutzer `pfadmin` und speichert die Verbindungszeichenkette in `../.state/t06.env` (nicht eingecheckt). Die Instanz ist öffentlich erreichbar, die Security Group lässt aber nur die eigene IP-Adresse zu, und die Verbindung ist mit TLS verschlüsselt (`sslmode=require`). Das Skript fragt die aktuelle Unterversion von PostgreSQL 18 ab und legt die Instanz damit an – dieselbe Hauptversion wie lokal.

PlaceFinder von Hand mit derselben Datenbank starten (im Ordner `/workspaces/placefinder`), etwa für die Karte (`http://localhost:5173/?api=http://localhost:8000`):

```bash
source ../cloud-labs-aws/.state/t06.env && export DATABASE_URL   # the database from create-db.sh
uv run fastapi dev src/placefinder/main.py                # meldet: Using PostGIS at <host>:5432/placefinder
```

**Zeiten vergleichen:** Lokal brauchen die Anfragen wenige Millisekunden. Mit der Datenbank beim Anbieter kommt für jede Abfrage mindestens ein Weg durchs Internet hinzu – die Zeiten von `./with-db.sh test-api.sh` zeigen, warum Anwendung und Datenbank in dieselbe Region und dasselbe Netz gehören (Termin 8).

**Backups:** RDS sichert täglich einen Snapshot und archiviert das WAL alle fünf Minuten. `create-db.sh` setzt die Aufbewahrung auf einen Tag (`--backup-retention-period 1`). `backups.sh` zeigt Einstellungen, Snapshots und das Zeitfenster für Point-in-Time Recovery. Eine Wiederherstellung legt eine **neue Instanz** an (`aws rds restore-db-instance-to-point-in-time`); das Skript zeigt den Befehl nur.

In der RDS-Konsole: *Monitoring* (CPU, Verbindungen), *Maintenance & backups* (automatische Backups, Point-in-Time-Recovery).

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| Karte zeigt die Basiskarte von OpenFreeMap | Parameter `tiles` fehlt oder ist nicht URL-kodiert. | Adresse aus `presign.sh` verwenden |
| Konsole des Browsers: CORS-Fehler | Die Karte läuft unter einer anderen Herkunft, z. B. `http://127.0.0.1:5173`. | Karte über `http://localhost:5173` öffnen |
| `403` trotz Signatur | Die URL ist abgelaufen oder wurde beim Kopieren verändert. | neue URL erzeugen, vollständig kopieren |
| `connection timeout expired`, psql hängt | Die eigene IP-Adresse hat sich geändert (neuer Tag, anderes Netz) und ist nicht freigegeben. | neue Adresse freigeben, siehe unten |
| `does not read DATABASE_URL yet` | PlaceFinder hat noch keine Datenbankanbindung. | Übung abschließen oder Tag `t06` auschecken |
| `Table places not found` | Die Datenbank ist leer. | `./with-db.sh load-cities.sh` |
| `Port 8006 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./with-db.sh test-api.sh --port 8007` |

Neue IP-Adresse freigeben:

```bash
source ../.state/t06.env   # SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 5432 \
  --cidr "$(curl --silent https://checkip.amazonaws.com)/32"
```

## Aufräumen

```bash
./destroy-bucket.sh         # Bucket mit allen Objekten
./destroy-db.sh             # ohne finalen Snapshot, automatische Backups werden gelöscht
../tools/find-leftovers.sh  # nothing left that costs money?
```

## Fragen zum Weiterdenken

- Warum ist eine Pre-Signed URL sicherer als ein öffentlicher Bucket, und wann ist sie trotzdem riskant?
- Welche Speicherklasse wäre für selten gelesene Rohdaten günstiger, und was kostet dann der Abruf?
- Wie würde CloudFront als CDN vor dem Bucket die Kosten für viele Kartenaufrufe senken?
- Warum braucht die Karte mit PMTiles keinen Kachelserver – und was ändert ein CDN davor an Kosten und Latenz?
- Welche Aufgaben übernimmt RDS gegenüber einer selbst betriebenen PostgreSQL-Instanz auf EC2 (Backups, Updates, Failover)?
- Was bedeuten RPO und RTO bei einer Backup-Aufbewahrung von einem Tag?
- Wie müsste das Netz aus Termin 4 aussehen, damit nur der Container-Dienst die Datenbank erreicht (privates Subnetz, sg-db)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Object Storage | S3 | Blob Storage | Cloud Storage |
| Zeitlich begrenzter Zugriff | Pre-Signed URL | SAS-Token | Signed URL |
| Privat | Block Public Access | `--allow-blob-public-access false` | Public Access Prevention |
| CORS | Bucket (`put-bucket-cors`) | Blob-Dienst des Kontos | Bucket (`--cors-file`) |
| Verwalteter Cache | ElastiCache for Valkey | Azure Managed Redis | Memorystore for Valkey |
| Dienst | RDS for PostgreSQL | Azure Database for PostgreSQL (Flexible Server) | Cloud SQL for PostgreSQL |
| Kleinste Größe | `db.t4g.micro` | `Standard_B1ms` | `db-f1-micro` (Edition Enterprise) |
| Zugang nur von der eigenen IP | Security Group | Firewall-Regel | autorisiertes Netz |
| PostGIS aktivieren | `CREATE EXTENSION` | erst freigeben (`azure.extensions`), dann `CREATE EXTENSION` | `CREATE EXTENSION` |
| Backups in der Übung | täglich, ein Tag Aufbewahrung | täglich, sieben Tage | täglich, sieben Backups |
| Point-in-Time Recovery | immer an; neue Instanz | immer an; neuer Server | mit `--enable-point-in-time-recovery`; Klon |
