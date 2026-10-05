# T07 – Object Storage mit Amazon S3

**Ziel:** Ein privater S3-Bucket für Rohdaten und Kartenkacheln, zeitlich begrenzter Zugriff über Pre-Signed URLs, Range Requests (Grundlage von PMTiles), CORS für den Abruf aus dem Browser und eine Lebenszyklusregel.

**Kosten:** Bei wenigen hundert Megabyte praktisch null (Speicher ca. 0,025 USD je GB und Monat in Frankfurt).

## Schritte

```bash
./create-bucket.sh                 # Bucket, CORS, Lebenszyklus, cities15000 nach raw/
./presign.sh                       # Pre-Signed URL, Test mit und ohne Signatur, Range Request
./upload.sh erfurt.pmtiles       # eigene Datei nach tiles/
./presign.sh tiles/erfurt.pmtiles
```

Eine PMTiles-Datei für eine Region lässt sich mit dem `pmtiles`-Werkzeug aus dem Dev Container aus dem täglichen Protomaps-Build schneiden, ohne den ganzen Planeten zu laden:

```bash
pmtiles extract https://build.protomaps.com/<YYYYMMDD>.pmtiles erfurt.pmtiles \
  --bbox=10.90,50.90,11.20,51.10 --maxzoom=14
```

Das aktuelle Datum steht unter <https://maps.protomaps.com/builds>.

## Was die Dateien einstellen

- `cors.json`: GET und HEAD von jeder Herkunft, Header `Range` erlaubt, `ETag` und `Content-Range` für den Browser sichtbar – nötig, damit MapLibre GL JS Kacheln per Range Request aus der Datei lesen kann.
- `lifecycle.json`: Objekte unter `raw/` werden nach 30 Tagen gelöscht, unvollständige Multipart-Uploads nach einem Tag.
- Neue Buckets blockieren öffentlichen Zugriff und verschlüsseln alle Objekte (SSE-S3); das Skript ändert daran nichts.

## Prüfen

Die Ausgabe von `presign.sh` zeigt:

- ohne Signatur: `403` – der Bucket ist privat,
- mit Signatur und `Range: bytes=0-99`: `206 Partial Content` mit `Content-Range`.

## Aufräumen

```bash
./destroy-bucket.sh
```

## Cache (Theorie)

Ein verwalteter Cache (Amazon ElastiCache for Valkey) kostet auch im kleinsten Ausbau jede Stunde Geld. Die Übung zum Caching läuft daher lokal mit Valkey im Dev Container; wer ElastiCache ausprobiert, löscht den Cache am selben Tag.

## Anbieterwechsel

Nach Termin 7 wechselt jeder Teilnehmer den Anbieter. Wer neu zu AWS kommt, arbeitet [t01-grundlagen](../t01-grundlagen/README.md) durch und liest die Zwischenpräsentation des Vorgängers. Wer AWS verlässt, prüft mit `../tools/find-leftovers.sh`, dass nichts mehr läuft.

## Fragen zum Weiterdenken

- Warum ist eine Pre-Signed URL sicherer als ein öffentlicher Bucket, und wann ist sie trotzdem riskant?
- Welche Speicherklasse wäre für selten gelesene Rohdaten günstiger, und was kostet dann der Abruf?
- Wie würde ein CDN (CloudFront) vor dem Bucket die Kosten für viele Kartenaufrufe senken?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Object Storage | S3 | Blob Storage | Cloud Storage |
| Zeitlich begrenzter Zugriff | Pre-Signed URL | SAS-Token | Signed URL |
| Cache | ElastiCache | Azure Managed Redis | Memorystore |
