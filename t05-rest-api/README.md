# T05 – API-Version ausrollen, testen und absichern

**Ziel:** Die REST-API aus Termin 5 (Stand `t05`: GeoJSON, Paginierung, ETags, Fehler nach RFC 9457) läuft auf dem Express-Mode-Dienst aus Termin 3. Ein Smoke-Test prüft die wichtigsten HTTP-Eigenschaften. Optional steht ein Amazon API Gateway mit Rate Limit davor.

**Kosten:** Dienst wie in Termin 3 (ca. 1 USD pro Tag). HTTP API: 1 USD je Million Aufrufe, die ersten Millionen im Free Tier.

## Voraussetzungen

- Dienst aus [t03-container](../t03-container/README.md) läuft (`../t03-container/deploy.sh`)
- Image `$PLACEFINDER_IMAGE:t05`

## Schritte

```bash
./update-service.sh          # Image t05 nach ECR, Dienst aktualisieren
./smoke-test.sh <service-url>
```

Express Mode rollt die neue Version als Canary aus: Ein Teil der Anfragen geht zuerst an die neuen Tasks, und bei vielen 5xx-Fehlern wird automatisch zurückgerollt. Die Dienst-URL steht in `../.state/t03.env` (`SERVICE_URL`).

Der Smoke-Test prüft Statuscodes (200, 404, 422), eine bedingte Anfrage mit `If-None-Match` (erwartet 304) und zeigt die Fehlerantwort im Format `application/problem+json`.

### Optional: API Gateway mit Rate Limit

```bash
./create-api-gateway.sh
./smoke-test.sh <api-url>
for i in $(seq 30); do curl --silent --output /dev/null --write-out '%{http_code} ' <api-url>/health; done; echo
./destroy-api-gateway.sh
```

Das Skript legt eine HTTP API an, die alle Pfade (`ANY /{proxy+}`) an den Dienst weiterreicht, und begrenzt die Stage auf 5 Anfragen pro Sekunde mit Spitzen bis 10. Die Schleife zeigt, wie das Gateway mit `429 Too Many Requests` antwortet.

## Aufräumen

```bash
./destroy-api-gateway.sh         # falls angelegt
../t03-container/destroy.sh      # Dienst, Load Balancer, ECR, Rollen
```

## Fragen zum Weiterdenken

- Welche Aufgaben übernimmt das API Gateway, die sonst in der Anwendung stünden (Rate Limits, Authentifizierung, Versionierung)?
- Warum liefert das Gateway bei zu vielen Anfragen 429 und nicht 503?
- Wie kommt die Client-IP-Adresse durch Load Balancer und Gateway bis zur Anwendung (`X-Forwarded-For`)?
- Was müsste man ergänzen, damit nur angemeldete Nutzer Favoriten anlegen dürfen (JWT-Authorizer)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| API-Gateway | API Gateway (HTTP API) | API Management (Consumption) | API Gateway |
| Rate Limit | Throttling je Stage oder Route | Richtlinie `rate-limit` | Kontingente mit API-Keys |
