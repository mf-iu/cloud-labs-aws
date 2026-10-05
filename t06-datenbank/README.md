# T06 – Verwaltete PostgreSQL-Datenbank mit PostGIS

**Ziel:** Eine Amazon-RDS-Instanz mit PostgreSQL, die Erweiterungen PostGIS und pg_trgm, die Tabelle `places` mit GeoNames `cities15000` sowie räumliche und unscharfe Abfragen – einmal mit und einmal ohne Index.

**Kosten:** `db.t4g.micro` mit 20 GB gp3 ca. 0,02 USD pro Stunde plus öffentliche IPv4-Adresse, aus dem Guthaben. **Nicht über Nacht laufen lassen.**

## Schritte

```bash
./create-db.sh        # Security Group (5432 nur von der eigenen IP), RDS-Instanz, ca. 10 min
./load-cities.sh      # cities15000 laden, Tabelle und Indizes anlegen
./query.sh            # Beispielabfragen aus queries.sql
./query.sh -i         # interaktive psql-Sitzung
```

`create-db.sh` erzeugt ein zufälliges Passwort und speichert die Verbindungszeichenkette in `../.state/t06.env` (nicht eingecheckt). Die Instanz ist öffentlich erreichbar, die Security Group lässt aber nur die eigene IP-Adresse zu, und die Verbindung ist mit TLS verschlüsselt (`sslmode=require`).

`load-cities.sh` lädt die Daten mit `\copy` (Bulk-Import über das COPY-Protokoll), ergänzt eine generierte Spalte `geom` vom Typ `geography(Point, 4326)`, die PostgreSQL aus Länge und Breite berechnet, und legt einen GiST-Index für räumliche Abfragen und einen GIN-Index mit Trigrammen für die unscharfe Namenssuche an.

### Lokale Datenbank und andere Dateien

Die Skripte nutzen `DATABASE_URL`, wenn die Variable gesetzt ist – zum Beispiel für die lokale PostGIS-Instanz aus `compose.yaml` (Termin 2; dort für die Datenbank `ports: ["127.0.0.1:5432:5432"]` ergänzen):

```bash
export DATABASE_URL=postgresql://pf:pf@localhost:5432/pf
export PGOPTIONS="-c jit=off -c max_parallel_workers_per_gather=0"   # einfache Pläne
./load-cities.sh
./query.sh
```

Andere GeoNames-Dateien lädt `./load-cities.sh <name>`; das Skript holt die Datei von GeoNames und ersetzt die Tabelle `places`. Statt eines Namens geht auch der Pfad einer vorhandenen Datei.

```bash
./load-cities.sh DE             # Länderdatei Deutschland, auch Berge, Seen, Ortsteile
./load-cities.sh allCountries   # rund 13 Millionen Einträge, Download ca. 400 MB
```

## Prüfen

`queries.sql` enthält:

1. die zehn nächsten Orte zu Erfurt (KNN-Suche mit `<->`),
2. eine Suche über `asciiname` ohne und mit B-Baum-Index (der Index wird mit `ROLLBACK` wieder entfernt),
3. alle Orte im Umkreis von 50 km mit `EXPLAIN ANALYZE` (Bitmap Index Scan),
4. dieselbe Umkreisabfrage mit abgeschaltetem Index (Seq Scan) zum Vergleich,
5. eine unscharfe Suche „Wuerzburg“ → „Würzburg“.

In der RDS-Konsole: *Monitoring* (CPU, Verbindungen), *Maintenance & backups* (automatische Backups, Point-in-Time-Recovery).

## Zusatz: POIs aus OpenStreetMap

`load-pois.sh` lädt einen Auszug von Geofabrik (Standard: Thüringen, ca. 150 MB) und importiert mit osm2pgsql (getestet mit 1.11 aus `sudo apt install osm2pgsql` unter Ubuntu 24.04 und mit 2.3) alle benannten Punkte mit `amenity`- oder `tourism`-Tag in die Tabelle `pois` (`pois.lua`) – in Thüringen rund 24.000. POIs, die als Fläche erfasst sind, fehlen. osm2pgsql schreibt `geometry`; `pois.sql` ergänzt deshalb eine Spalte `geog` vom Typ `geography` mit GiST-Index, damit Abstände in Metern gerechnet werden.

```bash
./load-pois.sh                                     # Thüringen
./load-pois.sh europe/germany/sachsen             # anderer Auszug
```

Für spätere Updates mit `osm2pgsql-replication` muss der Import mit `--slim` laufen. Daten © OpenStreetMap contributors, ODbL.

## Aufräumen

```bash
./destroy-db.sh       # ohne finalen Snapshot, automatische Backups werden gelöscht
```

## Fragen zum Weiterdenken

- Welche Aufgaben übernimmt RDS gegenüber einer selbst betriebenen PostgreSQL-Instanz auf EC2 (Backups, Updates, Failover)?
- Was bedeuten RPO und RTO bei einer Backup-Aufbewahrung von einem Tag?
- Warum ist die Abfrage mit Index schneller, obwohl beide dieselbe Funktion `ST_DWithin` verwenden?
- Wie müsste das Netz aus Termin 4 aussehen, damit nur der Container-Dienst die Datenbank erreicht (privates Subnetz, sg-db)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Dienst | RDS for PostgreSQL | Azure Database for PostgreSQL (Flexible Server) | Cloud SQL for PostgreSQL |
| Kleinste Größe | `db.t4g.micro` | `Standard_B1ms` | `db-f1-micro` |
| PostGIS aktivieren | `CREATE EXTENSION` | erst freigeben (`azure.extensions`), dann `CREATE EXTENSION` | `CREATE EXTENSION` |
