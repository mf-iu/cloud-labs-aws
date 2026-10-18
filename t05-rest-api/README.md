# T05 – Neue API-Version ausrollen, testen und absichern

**Ziel:** Der Stand `t05` von PlaceFinder – die REST-API v1 mit GeoJSON, Paginierung, ETags und Fehlern nach RFC 9457 – läuft auf dem Express-Mode-Dienst aus Termin 3. Ein Smoke-Test prüft die HTTP-Eigenschaften aus Termin 5 gegen die Cloud. Optional steht ein Amazon API Gateway mit Rate Limit davor.

| Skript | Aufgabe |
|---|---|
| `update-service.sh` | Image `t05` nach ECR kopieren, per Digest ausrollen, das Canary-Deployment abwarten, Smoke-Test starten; ohne Dienst aus Termin 3 legt es ihn an |
| `smoke-test.sh` | REST-API prüfen: Suche, Filter, Paginierung, ETag und 304, Problem Details, CORS, veraltete Version 0 – gegen jede URL, auch lokal |
| `create-api-gateway.sh`, `destroy-api-gateway.sh` | HTTP API mit Rate Limit vor dem Dienst anlegen und wieder löschen |
| `rate-limit-test.sh` | viele Anfragen gleichzeitig senden und die Antworten zählen: 200 und 429 |

**Kosten:** Dienst wie in Termin 3, ca. 1 USD pro Tag aus dem Guthaben – nach der Übung löschen. HTTP API: 1 USD je Million Aufrufe; die Übung kostet weniger als einen Cent.

## Voraussetzungen

- Image `$PLACEFINDER_IMAGE:t05` auf ghcr.io, öffentlich. Im Terminal des Dev Containers:
  ```bash
  cd /workspaces/placefinder
  git fetch upstream --tags                # Tag t05 der Musterlösung holen
  git switch --detach t05                  # oder den eigenen Stand verwenden
  ../cloud-labs-aws/t03-container/build-image.sh --push --tag t05
  git switch master
  ```
  `build-image.sh` lädt `placefinder:0.5.0` und `placefinder:t05` hoch; `upstream` einrichten: siehe [t02-vm](../t02-vm/README.md#container-und-compose).
- Der Dienst aus [t03-container](../t03-container/README.md) (Teil 2) darf noch laufen. Wurde er gelöscht, legt `update-service.sh` ihn neu an; die Voraussetzungen von dort gelten (Default-VPC).

## Schritte

```bash
cd /workspaces/cloud-labs-aws/t05-rest-api
./update-service.sh                      # ca. 10 Minuten, endet mit dem Smoke-Test
./smoke-test.sh                          # jederzeit wieder; ohne URL: der Dienst aus Termin 3
./smoke-test.sh http://localhost:8000    # dieselben Prüfungen gegen den lokalen Server
```

**Digest statt Tag:** `update-service.sh` rollt `…/pf-<owner>-placefinder@sha256:…` aus, nicht `…:t05`. Ein Tag lässt sich später auf ein anderes Image setzen, der Digest benennt genau dieses eine. So bleibt nachvollziehbar, welche Version läuft, und jeder neue Task startet dasselbe Image.

**Canary-Deployment:** Express Mode startet die neue Version neben der alten, leitet 5 % der Anfragen auf sie um und wartet 3 Minuten (Bake Time). Danach bekommt sie 100 %, nach weiteren 3 Minuten stoppen die alten Tasks. Liegt der Anteil der 4xx- und 5xx-Antworten dabei über 1 %, rollt ein Alarm automatisch zurück. Deshalb startet der Smoke-Test erst nach dem Deployment: Seine absichtlichen 404- und 422-Anfragen würden sonst als Fehler zählen.

**Smoke-Test:** Die Ausgabe zeigt je Prüfung `OK` oder `FAIL` mit dem erwarteten Wert, am Ende ein Beispiel für Problem Details. Geprüft werden Medientyp `application/geo+json`, Länge vor Breite, Umkreis und Bounding Box um Erfurt, der Link `next` im Header `Link` und im Body, `ETag` mit `304 Not Modified`, Fehler als `application/problem+json`, CORS für die Karte auf `http://localhost:5173` und die Header `Deprecation` und `Sunset` der Version 0.

**Karte mit den Daten aus der Cloud:** In PlaceFinder `python3 -m http.server 5173 --directory frontend` starten und `http://localhost:5173/?api=<SERVICE_URL>` öffnen. Die API erlaubt diese Herkunft über CORS (`CORS_ORIGINS`).

### Optional: API Gateway mit Rate Limit

```bash
./create-api-gateway.sh         # HTTP API vor dem Dienst
./smoke-test.sh --gateway       # dieselben Prüfungen über das Gateway
./rate-limit-test.sh            # 60 Anfragen, je 10 gleichzeitig: 200 und 429
./destroy-api-gateway.sh
```

Das Skript legt eine HTTP API an, die alle Pfade (`ANY /{proxy+}`) an den Dienst weiterreicht. Die Stage begrenzt die Rate auf 10 Anfragen pro Sekunde mit Spitzen bis 20 (Token Bucket). Das Limit gilt für alle Clients zusammen; Limits je Kunde mit API-Keys und Nutzungsplänen bieten nur die REST APIs von API Gateway (3,50 USD je Million Aufrufe). Über dem Limit antwortet das Gateway mit `429 Too Many Requests`.

## Typische Probleme

- `Cannot pull … without login`: Das Image fehlt auf ghcr.io oder ist privat – siehe Voraussetzungen.
- Smoke-Test meldet Version 0.1.x und viele `FAIL`: Der Dienst läuft noch mit dem Stand von Termin 3. Image mit `--tag t05` bauen, dann `./update-service.sh`.
- Deployment endet mit `ROLLBACK_SUCCESSFUL`: Die neue Version war nicht gesund (`/health`) oder lieferte zu viele Fehler. Logs in der ECS-Konsole unter *Clusters* → *default* → Dienst → *Logs*.
- `429` im Smoke-Test über das Gateway: kurz nach `rate-limit-test.sh` – einen Moment warten.

## Aufräumen

```bash
./destroy-api-gateway.sh         # falls angelegt
../t03-container/destroy.sh      # Dienst, Load Balancer, ECR, Rollen
```

## Fragen zum Weiterdenken

- Welche Aufgaben übernimmt das API Gateway, die sonst in der Anwendung stünden (Rate Limits, Authentifizierung, Versionierung)?
- Warum antwortet das Gateway bei zu vielen Anfragen mit 429 und nicht mit 503?
- Wie kommt die Client-IP-Adresse durch Gateway und Load Balancer bis zur Anwendung (`X-Forwarded-For`)?
- Welche Antworten des Smoke-Tests dürfte ein CDN zwischenspeichern, und wie lange (`Cache-Control`)?
- Was müsste man ergänzen, damit nur angemeldete Nutzer Favoriten anlegen dürfen (JWT-Authorizer)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Neue Version | Canary-Deployment mit automatischem Rollback | neue Revision | neue Revision, Traffic Splitting |
| API-Gateway | API Gateway (HTTP API) | API Management (Consumption) | API Gateway |
| Rate Limit | Throttling je Stage oder Route, für alle Clients zusammen | Richtlinie `rate-limit` je Abonnement | Kontingent je Projekt des API-Keys |
| Schlüssel | API-Keys nur bei REST APIs | Abonnementschlüssel im Header `Ocp-Apim-Subscription-Key` | API-Key, hier im Header `x-api-key` |
