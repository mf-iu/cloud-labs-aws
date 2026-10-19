# T07 – Object Storage, Cache und Kartenkacheln

**Ziel:** Object Storage lokal mit SeaweedFS und beim Anbieter mit Amazon S3 – privat, mit zeitlich begrenztem Zugriff, Range Requests und CORS. Darin liegen die Rohdaten von GeoNames und eine Kacheldatei (PMTiles), aus der die Karte von PlaceFinder ihre Basiskarte liest. Dazu Valkey als Cache für die Suchen von PlaceFinder und als Geo-Index im Vergleich mit PostGIS. Zum Schluss der Wechsel zum nächsten Anbieter.

| Skript | Aufgabe |
|---|---|
| `test-cache.sh` | PlaceFinder mit Valkey starten: jede Suche zweimal, `Cache-Status` und Zeiten, Smoke-Test aus Termin 5, Inhalt des Caches |
| `geosearch.sh` | Orte in Valkey laden (`GEOADD`) und die Umkreissuche mit `GEOSEARCH` neben PostGIS stellen |
| `make-tiles.sh` | Kacheln um Erfurt als PMTiles-Datei aus dem Tagesbuild von Protomaps schneiden |
| `local-s3.py` | lokaler Object Storage: CORS und Lebenszyklus, Upload, Pre-Signed URL mit Tests, Adresse der Karte |
| `create-bucket.sh`, `destroy-bucket.sh` | ein privater S3-Bucket beim Anbieter, mit CORS und Lebenszyklusregel; Rohdaten hochladen; alles wieder löschen |
| `upload.sh` | Datei hochladen: `.pmtiles` nach `tiles/`, alles andere nach `raw/` |
| `presign.sh` | Pre-Signed URL für eine Stunde, getestet ohne Signatur, mit Range Request und CORS; für PMTiles die Adresse der Karte |

Die ersten vier Skripte sind in allen drei Übungs-Repositories gleich und arbeiten mit den Diensten `valkey` und `seaweedfs` aus der `compose.yaml` von PlaceFinder.

**Kosten:** Teil 1 läuft lokal und kostet nichts. Teil 2: Speicher in Frankfurt ca. 0,025 USD je GB und Monat, dazu Anfragen und ausgehender Verkehr – bei einigen MB praktisch null, aus dem Guthaben. Ein verwalteter Cache (Amazon ElastiCache for Valkey) kostet auch im kleinsten Ausbau jede Stunde Geld; Valkey läuft deshalb nur lokal.

## Teil 1: lokal (Übung im Termin)

Valkey und SeaweedFS laufen als Dienste in der `compose.yaml` von PlaceFinder. Die Musterlösung ab Tag `t07` enthält sie; im eigenen Fork diese Dienste und das Volume `s3data` ergänzen:

```yaml
services:
  # api, web and db as before; api with VALKEY_URL: valkey://valkey:6379/0
  valkey:
    image: valkey/valkey:9.0
    # a cache: memory only, nothing saved to disk; when 64 MB are full,
    # Valkey drops the least recently used keys
    command: >-
      valkey-server --save "" --appendonly no
      --maxmemory 64mb --maxmemory-policy allkeys-lru
    ports: ["127.0.0.1:6379:6379"]       # reachable from this computer only
    healthcheck:
      test: valkey-cli ping
      interval: 5s
  seaweedfs:
    image: chrislusf/seaweedfs:4.48
    # all components in one process: master, volume server, filer and the
    # S3 API on port 8333; WebDAV, admin UI and table catalogs are not needed
    command: >-
      mini -dir=/data -webdav=false -admin.ui=false
      -s3.port.iceberg=0 -s3.port.lance=0
    environment:
      # with credentials every request must be signed: the bucket is private
      AWS_ACCESS_KEY_ID: placefinder
      AWS_SECRET_ACCESS_KEY: placefinder-local    # local development only
      S3_BUCKET: placefinder                      # created at startup
    ports: ["127.0.0.1:8333:8333"]       # S3 API, from this computer only
    volumes: [s3data:/data]
    healthcheck:
      test: curl --fail --silent --output /dev/null http://127.0.0.1:8333/healthz
      interval: 5s

volumes:
  www:
  pgdata:
  s3data:
```

```bash
(cd /workspaces/placefinder && docker compose up --detach --wait db valkey seaweedfs)
cd /workspaces/cloud-labs-aws/t07-objektspeicher
export DATABASE_URL=postgresql://pf:pf@localhost:5432/pf   # PostGIS aus Termin 6
./test-cache.sh                                  # Cache: erst Miss, dann Hit; Smoke-Test
./geosearch.sh                                   # GEOSEARCH in Valkey neben PostGIS
uv run local-s3.py setup                         # CORS und Lebenszyklus für den Bucket placefinder
uv run local-s3.py upload ../.state/data/cities15000.txt   # Rohdaten nach raw/
./make-tiles.sh                                  # erfurt.pmtiles, wenige MB
uv run local-s3.py upload ../.state/data/erfurt.pmtiles    # nach tiles/
uv run local-s3.py presign tiles/erfurt.pmtiles  # ohne Signatur 403, Range 206, CORS
uv run local-s3.py map tiles/erfurt.pmtiles      # Adresse der Karte mit den eigenen Kacheln
```

Die Karte braucht PlaceFinder auf Port 8000 und einen Webserver für `frontend/` auf Port 5173 (siehe README von PlaceFinder, Abschnitt „Karte“):

```bash
cd /workspaces/placefinder
VALKEY_URL=valkey://localhost:6379/0 uv run fastapi dev src/placefinder/main.py   # Terminal 1: API auf Port 8000
python3 -m http.server 5173 --directory frontend                                  # Terminal 2: Karte auf Port 5173
```

### Cache: `test-cache.sh`

Das Skript leert den Cache, startet PlaceFinder auf Port 8007 mit Valkey – mit der Datenbank aus `DATABASE_URL` bzw. aus Termin 6, sonst mit der Datei im Speicher – und sendet drei Suchen je zweimal. Die erste Anfrage geht an die Datenbank (`Cache-Status: PlaceFinder; fwd=uri-miss; stored`), die zweite beantwortet Valkey (`PlaceFinder; hit`). Danach läuft der Smoke-Test aus Termin 5: Mit Cache muss die API genau dieselben Antworten geben. Zum Schluss zeigt das Skript Schlüssel, verbleibende Lebensdauer (TTL), Treffer und Fehlschläge (`keyspace_hits`, `keyspace_misses`) und den Speicherbedarf.

Von Hand:

```bash
cd /workspaces/placefinder
docker compose exec valkey valkey-cli --scan --pattern 'placefinder:*'    # Schlüssel
docker compose exec valkey valkey-cli ttl 'placefinder:v1:/v1/places?q=Erfurt'
docker compose exec valkey valkey-cli monitor                              # alle Befehle live, Strg+C
docker compose exec valkey valkey-cli flushdb                              # Cache leeren
```

### Geo-Index: `geosearch.sh`

`GEOADD` speichert jeden Ort in einem Sorted Set; der Score ist ein 52-Bit-Geohash aus Länge und Breite. Nahe Orte haben ähnliche Geohashes – `GEOSEARCH` sucht deshalb nur in wenigen Bereichen des Sets. Das Skript lädt alle Orte von `cities15000` in einem Strom (`valkey-cli --pipe`), zeigt Geohash und Score von Erfurt und die zehn nächsten Orte im Umkreis von 25 km, dann dieselbe Suche in PostGIS. Die Abstände weichen leicht ab: Valkey rechnet auf einer Kugel, PostGIS mit `geography` auf dem Ellipsoid WGS 84. Der Index belegt rund 4 MB im Speicher; bei vollem Speicher kann `allkeys-lru` ihn verdrängen.

### Object Storage lokal: `local-s3.py`

SeaweedFS spricht die S3-API; jeder S3-Client funktioniert damit. `local-s3.py` nutzt boto3, das AWS-SDK für Python; `uv run` installiert es beim ersten Aufruf (Abhängigkeiten im Kopf der Datei, PEP 723). Endpunkt und Schlüssel stammen aus der `compose.yaml`, nicht aus der Anmeldung beim Anbieter.

- **Privat:** Mit den Zugangsdaten in der `compose.yaml` verlangt SeaweedFS für jede Anfrage eine Signatur. Ohne Signatur antwortet es mit `403`.
- **Pre-Signed URL:** Die Signatur steht in der URL (`X-Amz-Algorithm`, `X-Amz-Credential`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-Signature`). Wer die URL hat, darf genau dieses Objekt lesen, bis sie abläuft (`presign`: eine Stunde, `map`: ein Tag; höchstens sieben Tage).
- **Range Request:** `Range: bytes=0-99` liefert `206 Partial Content` und nur diese Bytes – die Grundlage von PMTiles.
- **CORS:** Die Karte auf `http://localhost:5173` liest den Bucket auf Port 8333, also von einer anderen Herkunft. `setup` erlaubt genau diese Herkunft mit dem Header `Range`; `presign` prüft das mit einer Preflight-Anfrage (`OPTIONS`).
- **Lebenszyklus:** Objekte unter `raw/` löscht SeaweedFS nach 30 Tagen.

### Kacheln: `make-tiles.sh`

Protomaps baut jeden Tag eine Kacheldatei der ganzen Erde aus OpenStreetMap (rund 130 GB, PMTiles). `pmtiles extract` liest daraus mit Range Requests nur die Kacheln einer Bounding Box bis zur gewählten Zoomstufe und schreibt sie in eine neue Datei – für Erfurt (10,90–11,20° Länge, 50,90–51,10° Breite) bis Zoomstufe 14 einige MB. Andere Gebiete: `./make-tiles.sh <min_lon,min_lat,max_lon,max_lat> [maxzoom]`, dann `region.pmtiles`. Daten © OpenStreetMap-Mitwirkende, ODbL.

## Teil 2: beim eigenen Anbieter (Selbstlernphase)

```bash
cd /workspaces/cloud-labs-aws/t07-objektspeicher
./create-bucket.sh                          # Bucket mit CORS und Lebenszyklus, cities15000 nach raw/
./upload.sh ../.state/data/erfurt.pmtiles   # nach tiles/
./presign.sh tiles/erfurt.pmtiles           # Tests und Adresse der Karte
./presign.sh                                # dasselbe für die Rohdaten in raw/geonames/
./destroy-bucket.sh                         # danach alles löschen
```

Die Adresse der Karte, die `presign.sh` ausgibt, im Browser öffnen, während PlaceFinder und der Webserver für `frontend/` laufen (siehe oben). Die Karte lädt dann ihre Kacheln direkt aus dem Object Storage des Anbieters – ohne eigenen Server dafür.

**Was die Skripte einstellen:**

- Neue Buckets blockieren öffentlichen Zugriff (*Block Public Access*) und verschlüsseln jedes Objekt (SSE-S3); das Skript ändert daran nichts.
- `cors.json`: GET und HEAD von `http://localhost:5173`, Header `Range` erlaubt, `ETag`, `Content-Length` und `Content-Range` für den Browser sichtbar.
- `lifecycle.json`: Objekte unter `raw/` werden nach 30 Tagen gelöscht, unvollständige Multipart-Uploads nach einem Tag.
- `presign.sh` signiert mit den Zugangsdaten der AWS CLI (Signature Version 4). Die URL gilt höchstens so lange wie diese Zugangsdaten – bei kurzlebigen Anmeldungen (SSO) auch kürzer als die angegebene Stunde.

**Prüfen:** Die Ausgabe von `presign.sh` zeigt ohne Signatur `403` – das Objekt ist privat –, mit Signatur und `Range: bytes=0-99` die Antwort `206 Partial Content` mit `Content-Range` und bei der Preflight-Anfrage `Access-Control-Allow-Origin: http://localhost:5173`.

## Anbieterwechsel

Ab Termin 8 arbeitet jeder Teilnehmer mit dem nächsten Anbieter (Termin 0, Folie 8): Wer bisher AWS hatte, wechselt zu **Azure** und arbeitet mit [cloud-labs-azure](https://github.com/mf-iu/cloud-labs-azure) weiter; zu AWS kommt der Vorgänger. Das Konto beim bisherigen Anbieter bleibt bestehen, aber leer. Die Testphase beim neuen Anbieter beginnt mit dem Anlegen des Kontos – nicht früher als nötig, Azure gewährt nur 30 Tage.

**Beim bisherigen Anbieter, vor dem Wechsel:**

1. Alles löschen, was noch läuft: die `destroy-…`-Skripte der Termine 2–7.
2. `../tools/find-leftovers.sh` – zeigt nichts mehr an, was Geld kostet.
3. Budget-Alarm und Zugangsdaten bleiben; die Folien der Zwischenpräsentation gehen an den Nachfolger.

**Beim neuen Anbieter:**

1. Das Übungs-Repository des neuen Anbieters klonen, neben `placefinder` (im Ubuntu-Fenster: `git clone https://github.com/mf-iu/cloud-labs-azure.git`), und in VS Code im Dev Container öffnen.
2. `config.example.env` nach `config.env` kopieren und ausfüllen.
3. [t01-grundlagen](../t01-grundlagen/README.md) durcharbeiten: Konto bzw. Testphase, Budget-Alarm, Anmeldung der CLI, `t01-grundlagen/check-cli.sh`.
4. Die Folien des Vorgängers lesen, besonders die Übergabe-Checkliste.

PlaceFinder bleibt derselbe Fork; das Image auf ghcr.io kann jeder Anbieter laden.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No answer from http://localhost:8333` | SeaweedFS läuft nicht. | `docker compose up --detach --wait seaweedfs` in `/workspaces/placefinder` |
| `has no cache yet` | PlaceFinder kennt `VALKEY_URL` noch nicht. | Übung abschließen oder Tag `t07` auschecken |
| Karte zeigt die Basiskarte von OpenFreeMap | Parameter `tiles` fehlt oder ist nicht URL-kodiert. | Adresse aus `local-s3.py map` bzw. `presign.sh` verwenden |
| Konsole des Browsers: CORS-Fehler | Die Karte läuft unter einer anderen Herkunft, z. B. `http://127.0.0.1:5173`. | Karte über `http://localhost:5173` öffnen |
| `403` trotz Signatur | Die URL ist abgelaufen oder wurde beim Kopieren verändert. | neue URL erzeugen, vollständig kopieren |
| `Port 8007 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./test-cache.sh --port 8008` |

## Aufräumen

```bash
./destroy-bucket.sh                            # Bucket mit allen Objekten
cd /workspaces/placefinder && docker compose down   # lokal; die Volumes bleiben
```

## Fragen zum Weiterdenken

- Wie lange darf eine Suche im Cache bleiben? Was spricht für 5 Sekunden, was für einen Tag?
- Nach einem neuen `load-cities.sh` liefert der Cache noch alte Antworten. Welche Konsistenz bietet PlaceFinder damit – und wie ließe sich der Cache gezielt leeren?
- Warum ist eine Pre-Signed URL sicherer als ein öffentlicher Bucket, und wann ist sie trotzdem riskant?
- Welche Speicherklasse wäre für selten gelesene Rohdaten günstiger, und was kostet dann der Abruf?
- Wie würde CloudFront als CDN vor dem Bucket die Kosten für viele Kartenaufrufe senken?
- Warum braucht die Karte mit PMTiles keinen Kachelserver – und was ändert ein CDN davor an Kosten und Latenz?

## Andere Anbieter

| | AWS | Azure | Google Cloud | lokal |
|---|---|---|---|---|
| Object Storage | S3 | Blob Storage | Cloud Storage | SeaweedFS (S3-API) |
| Zeitlich begrenzter Zugriff | Pre-Signed URL | SAS-Token | Signed URL | Pre-Signed URL |
| Privat | Block Public Access | `--allow-blob-public-access false` | Public Access Prevention | Zugangsdaten gesetzt |
| CORS | Bucket (`put-bucket-cors`) | Blob-Dienst des Kontos | Bucket (`--cors-file`) | Bucket (`put_bucket_cors`) |
| Verwalteter Cache | ElastiCache for Valkey | Azure Managed Redis | Memorystore for Valkey | Valkey |
