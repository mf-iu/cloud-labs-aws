# T06 – Verwaltete PostgreSQL-Datenbank mit PostGIS

**Ziel:** Eine Amazon-RDS-Instanz mit PostgreSQL 18, die Erweiterungen PostGIS und pg_trgm, die Tabelle `places` mit GeoNames `cities15000` sowie räumliche und unscharfe Abfragen – einmal mit und einmal ohne Index. PlaceFinder (Stand `t06`) liest die Orte aus dieser Datenbank; der Smoke-Test aus Termin 5 prüft, dass die API gleich bleibt.

| Skript | Aufgabe |
|---|---|
| `create-db.sh`, `destroy-db.sh` | PostgreSQL 18 beim Anbieter anlegen, nur von der eigenen IP-Adresse erreichbar, und wieder löschen |
| `load-cities.sh` | Tabelle `places` anlegen, GeoNames per `\copy` laden, Geometrie und Indizes ergänzen |
| `query.sh` | Beispielabfragen aus `queries.sql` ausführen oder eine interaktive psql-Sitzung öffnen |
| `test-api.sh` | PlaceFinder lokal mit dieser Datenbank starten und mit dem Smoke-Test aus Termin 5 prüfen |
| `backups.sh` | automatische Backups und das Zeitfenster für Point-in-Time Recovery anzeigen; ändert nichts |
| `load-pois.sh` | Zusatz: POIs aus OpenStreetMap laden |

Alle Skripte außer `create-db.sh`, `destroy-db.sh` und `backups.sh` nutzen `DATABASE_URL`, wenn die Variable gesetzt ist, sonst die Datenbank aus `create-db.sh`.

**Kosten:** Teil 1 läuft lokal und kostet nichts. Teil 2: `db.t4g.micro` mit 20 GB gp3 ca. 0,02 USD pro Stunde plus öffentliche IPv4-Adresse, aus dem Guthaben. **Nicht über Nacht laufen lassen.**

## Teil 1: lokal mit Compose (Übung im Termin)

Lokal läuft PostgreSQL mit PostGIS als Dienst `db` in der `compose.yaml` von PlaceFinder. In Termin 2 enthielt sie nur `api` und den Übungsdienst `web`; jetzt kommen `db` und das Volume `pgdata` dazu. `web` braucht PlaceFinder nicht, er kann bleiben oder entfallen. Die Musterlösung ab Tag `t06` enthält den Dienst schon.

```yaml
services:
  # api (and web) as before
  db:
    image: postgis/postgis:18-3.6        # PostgreSQL 18 with PostGIS 3.6 (amd64 only)
    environment:
      POSTGRES_USER: pf
      POSTGRES_PASSWORD: pf              # plain text for local development only
      POSTGRES_DB: pf
    ports: ["127.0.0.1:5432:5432"]       # reachable from this computer only
    # from PostgreSQL 18 on, the volume belongs at /var/lib/postgresql
    volumes: [pgdata:/var/lib/postgresql]
    healthcheck:
      # --host 127.0.0.1: check via TCP, the init server only listens on the socket
      test: pg_isready --host 127.0.0.1 --username pf
      interval: 5s

volumes:
  www:
  pgdata:
```

```bash
(cd /workspaces/placefinder && docker compose up --detach db)   # db: healthy in docker compose ps
cd /workspaces/cloud-labs-aws/t06-datenbank
export DATABASE_URL=postgresql://pf:pf@localhost:5432/pf
export PGOPTIONS="--jit=off --max_parallel_workers_per_gather=0"   # einfache Pläne
./load-cities.sh          # cities15000 laden, Tabelle und Indizes anlegen, wenige Sekunden
./query.sh                # Beispielabfragen aus queries.sql
./query.sh --interactive  # interaktive psql-Sitzung
./test-api.sh             # PlaceFinder mit dieser Datenbank, sobald db.py fertig ist
```

`load-cities.sh` lädt die Daten mit `\copy` (Bulk-Import über das COPY-Protokoll; die Datei bleibt auf dem eigenen Rechner), ergänzt eine generierte Spalte `geom` vom Typ `geography(Point, 4326)`, die PostgreSQL aus Länge und Breite berechnet, und legt danach die Indizes an (`indexes.sql`):

| Index | Art | Wofür | Größe bei cities15000 |
|---|---|---|---|
| `places_geom_idx` | GiST auf `geom` | Umkreis und nächste Nachbarn | ca. 2,5 MB |
| `places_name_trgm_idx` | GIN mit Trigrammen auf `name` | unscharfe Suche (`%`, `similarity`) in `queries.sql` | ca. 2 MB |
| `places_all_names_trgm_idx` | GIN mit Trigrammen auf allen Namen | Namenssuche von PlaceFinder, auch über `alternatenames` (München → Munich) | ca. 19 MB |

Die Tabelle selbst ist rund 11 MB groß. Der Index auf allen Namen ist größer als die Tabelle, weil große Städte Hunderte von Schreibweisen haben – Indizes kosten Speicher. Sein Ausdruck muss genau dem in `src/placefinder/db.py` (`ALL_NAMES`) entsprechen, sonst nutzt PostgreSQL ihn nicht.

Andere GeoNames-Dateien lädt `./load-cities.sh <name>`; das Skript holt die Datei von GeoNames und ersetzt die Tabelle `places`. Statt eines Namens geht auch der Pfad einer vorhandenen Datei.

```bash
./load-cities.sh DE             # Länderdatei Deutschland, auch Berge, Seen, Ortsteile
./load-cities.sh allCountries   # rund 13 Millionen Einträge, Download ca. 400 MB – nur lokal
```

Bei `allCountries` dauern Import und Indizes einige Minuten und belegen mehrere GB; dafür ist die kleine Instanz beim Anbieter nicht gedacht.

## Teil 2: beim eigenen Anbieter (Selbstlernphase)

```bash
cd /workspaces/cloud-labs-aws/t06-datenbank
unset DATABASE_URL        # sonst arbeiten die Skripte weiter mit der lokalen Datenbank
./create-db.sh            # Security Group (5432 nur von der eigenen IP), RDS-Instanz, ca. 10 min
./load-cities.sh          # dieselben Daten, jetzt über das Internet
./query.sh                # Zeiten mit der lokalen Datenbank vergleichen
./test-api.sh             # PlaceFinder lokal, die Daten aus der Cloud
./backups.sh              # Backups und Point-in-Time Recovery
./destroy-db.sh           # danach löschen
```

`create-db.sh` erzeugt ein zufälliges Passwort für den Benutzer `pfadmin` und speichert die Verbindungszeichenkette in `../.state/t06.env` (nicht eingecheckt). Die Instanz ist öffentlich erreichbar, die Security Group lässt aber nur die eigene IP-Adresse zu, und die Verbindung ist mit TLS verschlüsselt (`sslmode=require`). Das Skript fragt die aktuelle Unterversion von PostgreSQL 18 ab und legt die Instanz damit an – dieselbe Hauptversion wie lokal.

## PlaceFinder mit der Datenbank

Ab Tag `t06` liest PlaceFinder die Orte aus PostgreSQL, wenn `DATABASE_URL` gesetzt ist – sonst wie bisher aus der Datei. `test-api.sh` startet PlaceFinder aus `/workspaces/placefinder` auf Port 8006 mit der Datenbank dieser Übung, wartet auf `/health`, führt den Smoke-Test aus [t05-rest-api](../t05-rest-api/README.md) aus, misst drei typische Anfragen und hält den Server wieder an. `DATA_FILE` zeigt dabei auf eine Datei, die es nicht gibt: Ein PlaceFinder, der `DATABASE_URL` übersieht, startet so gar nicht erst.

Voraussetzung ist ein Stand von PlaceFinder, der `DATABASE_URL` liest – der eigene aus der Übung oder die Musterlösung:

```bash
cd /workspaces/placefinder
git fetch upstream --tags                # Tag t06 der Musterlösung holen
git switch --detach t06                  # oder den eigenen Stand verwenden
../cloud-labs-aws/t06-datenbank/test-api.sh
git switch master
```

Von Hand mit derselben Datenbank, etwa für die Karte (`http://localhost:5173/?api=http://localhost:8000`):

```bash
source ../cloud-labs-aws/.state/t06.env && export DATABASE_URL   # die Datenbank aus create-db.sh
uv run fastapi dev src/placefinder/main.py                # meldet: Using PostGIS at <host>:5432/placefinder
```

**Zeiten vergleichen:** Lokal brauchen die Anfragen wenige Millisekunden. Mit der Datenbank beim Anbieter kommt für jede Abfrage mindestens ein Weg durchs Internet hinzu – die Zeiten von `test-api.sh` zeigen, warum Anwendung und Datenbank in dieselbe Region und dasselbe Netz gehören (Termin 8).

## Prüfen

`queries.sql` enthält:

1. die zehn nächsten Orte zu Erfurt (KNN-Suche mit `<->`),
2. eine Suche über `asciiname` ohne und mit B-Baum-Index (der Index wird mit `ROLLBACK` wieder entfernt),
3. alle Orte im Umkreis von 50 km mit `EXPLAIN ANALYZE` (Bitmap Index Scan),
4. dieselbe Umkreisabfrage mit abgeschaltetem Index (Seq Scan) zum Vergleich,
5. eine unscharfe Suche „Wuerzburg“ → „Würzburg“.

**Backups:** RDS sichert täglich einen Snapshot und archiviert das WAL alle fünf Minuten. `create-db.sh` setzt die Aufbewahrung auf einen Tag (`--backup-retention-period 1`). `backups.sh` zeigt Einstellungen, Snapshots und das Zeitfenster für Point-in-Time Recovery. Eine Wiederherstellung legt eine **neue Instanz** an (`aws rds restore-db-instance-to-point-in-time`); das Skript zeigt den Befehl nur.

In der RDS-Konsole: *Monitoring* (CPU, Verbindungen), *Maintenance & backups* (automatische Backups, Point-in-Time-Recovery).

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `connection timeout expired`, psql hängt | Die eigene IP-Adresse hat sich geändert (neuer Tag, anderes Netz) und ist nicht freigegeben. | neue Adresse freigeben, siehe unten |
| Skripte arbeiten mit der lokalen statt der Cloud-Datenbank | `DATABASE_URL` ist im Terminal noch gesetzt. | `unset DATABASE_URL` |
| `does not read DATABASE_URL yet` | PlaceFinder hat noch keine Datenbankanbindung. | Übung abschließen oder Tag `t06` auschecken |
| `Table places not found` | Die Datenbank ist leer. | `./load-cities.sh` |
| `Port 8006 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./test-api.sh --port 8007` |

Neue IP-Adresse freigeben:

```bash
source ../.state/t06.env   # SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 5432 \
  --cidr "$(curl --silent https://checkip.amazonaws.com)/32"
```

## Zusatz: POIs aus OpenStreetMap

`load-pois.sh` lädt einen Auszug von Geofabrik (Standard: Thüringen, ca. 150 MB) und importiert mit osm2pgsql (getestet mit 1.11 aus `sudo apt install osm2pgsql` unter Ubuntu 24.04 und mit 2.3) alle benannten Punkte mit `amenity`- oder `tourism`-Tag in die Tabelle `pois` (`pois.lua`) – in Thüringen rund 24.000. POIs, die als Fläche erfasst sind, fehlen. osm2pgsql schreibt `geometry`; `pois.sql` ergänzt deshalb eine Spalte `geog` vom Typ `geography` mit GiST-Index, damit Abstände in Metern gerechnet werden.

```bash
./load-pois.sh                                     # Thüringen
./load-pois.sh europe/germany/sachsen              # anderer Auszug
```

Für spätere Updates mit `osm2pgsql-replication` muss der Import mit `--slim` laufen. Daten © OpenStreetMap contributors, ODbL.

## Aufräumen

```bash
./destroy-db.sh       # ohne finalen Snapshot, automatische Backups werden gelöscht
docker compose --file /workspaces/placefinder/compose.yaml down   # lokal; das Volume pgdata bleibt
```

## Fragen zum Weiterdenken

- Welche Aufgaben übernimmt RDS gegenüber einer selbst betriebenen PostgreSQL-Instanz auf EC2 (Backups, Updates, Failover)?
- Was bedeuten RPO und RTO bei einer Backup-Aufbewahrung von einem Tag?
- Warum ist die Abfrage mit Index schneller, obwohl beide dieselbe Funktion `ST_DWithin` verwenden?
- Warum öffnet PlaceFinder einen Pool von Verbindungen beim Start, statt für jede Anfrage eine neue Verbindung aufzubauen?
- Wie müsste das Netz aus Termin 4 aussehen, damit nur der Container-Dienst die Datenbank erreicht (privates Subnetz, sg-db)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Dienst | RDS for PostgreSQL | Azure Database for PostgreSQL (Flexible Server) | Cloud SQL for PostgreSQL |
| Kleinste Größe | `db.t4g.micro` | `Standard_B1ms` | `db-f1-micro` (Edition Enterprise) |
| Zugang nur von der eigenen IP | Security Group | Firewall-Regel | autorisiertes Netz |
| PostGIS aktivieren | `CREATE EXTENSION` | erst freigeben (`azure.extensions`), dann `CREATE EXTENSION` | `CREATE EXTENSION` |
| Backups in der Übung | täglich, ein Tag Aufbewahrung | täglich, sieben Tage | täglich, sieben Backups |
| Point-in-Time Recovery | immer an; neue Instanz | immer an; neuer Server | mit `--enable-point-in-time-recovery`; Klon |
