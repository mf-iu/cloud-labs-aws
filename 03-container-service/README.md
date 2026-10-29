# 03 – Container-Dienst: Registry, Serverless Container, neue Versionen

Zwei Teile und ein Zusatz: In Termin 3 kommt das Image von PlaceFinder auf den Container-Dienst von AWS. In Termin 5 rollt jeder seinen eigenen Stand der REST-API per Digest auf demselben Dienst aus, prüft ihn mit dem Smoke-Test und löscht den Dienst wieder. Das API-Gateway mit Rate Limit ist **Zusatz** – freiwillig und ohne Folgen für spätere Termine.

Was nicht vom Anbieter abhängt, steht in `cloud-labs-local`: das Image bauen und nach ghcr.io laden ([02-container](https://github.com/mf-iu/cloud-labs-local/tree/master/02-container)), Kubernetes lokal mit k3d ([03-kubernetes](https://github.com/mf-iu/cloud-labs-local/tree/master/03-kubernetes)), der Filter und die lokalen Prüfungen ([05-rest-api](https://github.com/mf-iu/cloud-labs-local/tree/master/05-rest-api)). Smoke-Test und Lasttest kommen aus `cloud-labs-local/tools`; die gleichnamigen Skripte hier rufen sie mit der Adresse des Dienstes auf.

| Skript | Aufgabe |
|---|---|
| `push-image.sh` | ECR-Repository anlegen, Image von ghcr.io hineinkopieren |
| `deploy.sh`, `destroy.sh` | Dienst mit ECS Express Mode anlegen und auf `/health` warten; Dienst, Repository und Rollen löschen |
| `update-service.sh` | Image `t05` nach ECR kopieren, per Digest ausrollen, das Canary-Deployment abwarten, Smoke-Test starten; ohne Dienst aus Termin 3 legt es ihn an |
| `smoke-test.sh` | Smoke-Test aus `cloud-labs-local/tools` gegen den Dienst; mit `--gateway` gegen das API-Gateway mit Schlüssel |
| `create-api-gateway.sh`, `destroy-api-gateway.sh` | HTTP API mit Rate Limit vor dem Dienst anlegen und wieder löschen |
| `rate-limit-test.sh` | Lasttest aus `cloud-labs-local/tools` gegen das API-Gateway: viele Anfragen gleichzeitig, Antworten 200 und 429 |

## Teil 1: Registry und ECS Express Mode (Termin 3, Selbstlernphase)

**Ziel:** Das PlaceFinder-Image liegt in Amazon ECR und läuft mit **Amazon ECS Express Mode** auf Fargate. Express Mode legt mit einem Aufruf Task Definition, Dienst, Application Load Balancer mit HTTPS-Zertifikat, Autoscaling und Logs an.

**Kosten:** Fargate-Task mit 0,25 vCPU und 512 MB ca. 0,01 USD pro Stunde, Load Balancer ca. 0,03 USD pro Stunde plus öffentliche IPv4-Adressen – zusammen etwa 1 USD pro Tag aus dem Guthaben. ECR: 500 MB im Free Tier. **Nach der Übung löschen.**

AWS App Runner nimmt seit 30. April 2026 keine neuen Kunden mehr an; AWS empfiehlt stattdessen ECS Express Mode.

### Voraussetzungen

- Docker im Dev Container
- Image `$PLACEFINDER_IMAGE:t03` auf ghcr.io: `/workspaces/cloud-labs-local/02-container/publish-image.sh`, danach das Paket auf GitHub öffentlich machen (*Packages* → *placefinder* → *Package settings* → *Change visibility*). Das Skript prüft, ob das geklappt hat.
- Das Konto hat eine Default-VPC (Standard bei neuen Konten). Express Mode legt Load Balancer und Tasks dort an.

### Schritte

```bash
./push-image.sh                 # ECR-Repository anlegen, Image hochladen
./deploy.sh                     # Express-Mode-Dienst anlegen, auf /health warten
```

`push-image.sh` legt das Repository mit Schwachstellen-Scan beim Push und einer Lebenszyklusregel an, die nur die fünf neuesten Images behält. `deploy.sh` legt zwei IAM-Rollen an: die Execution Role, mit der ECS das Image lädt und Logs schreibt, und die Infrastructure Role, mit der Express Mode Load Balancer und Autoscaling verwaltet.

Der erste Start dauert etwa fünf Minuten. Der Status lässt sich verfolgen mit:

```bash
aws ecs describe-express-gateway-service --service-arn <arn> --query service.status
```

### Prüfen

```bash
url=$(grep SERVICE_URL ../.state/t03.env | cut --delimiter = --fields 2)
curl "$url/health"
curl "$url/places?q=Erfurt"
aws ecr describe-image-scan-findings --repository-name pf-<owner>-placefinder --image-id imageTag=t03
```

In der ECS-Konsole unter *Clusters* → *default* sind Dienst, Tasks, Load Balancer und Logs zu sehen.

### Aufräumen

```bash
./destroy.sh     # Dienst (inkl. Load Balancer), Log-Gruppe, ECR-Repository, Rollen
```

Wer in Termin 5 weiterarbeiten will, kann den Dienst bis dahin stehen lassen – das kostet dann aber etwa 1 USD pro Tag.

### Fragen zum Weiterdenken

- Warum skaliert ECS Express Mode nicht auf null, Cloud Run und Azure Container Apps dagegen schon? Was bedeutet das für die Kosten?
- Welche Ressourcen hat Express Mode im Hintergrund angelegt (*EC2* → *Load Balancers*, *Target Groups*, *Security Groups*)?
- Wofür ist die Infrastructure Role nötig, und warum muss sie beim Löschen als Letztes entfernt werden?

## Teil 2: eigenen Stand ausrollen, prüfen, löschen (Termin 5)

**Ziel:** Der eigene Stand von PlaceFinder – der Tag `t05` mit einem zusätzlichen Filter – läuft auf dem Express-Mode-Dienst aus Termin 3. Ein Smoke-Test prüft die HTTP-Eigenschaften aus Termin 5 gegen die Cloud. Als Zusatz steht ein Amazon API Gateway mit Rate Limit davor.

**Kosten:** Dienst wie in Termin 3, ca. 1 USD pro Tag aus dem Guthaben – nach der Übung löschen. HTTP API: 1 USD je Million Aufrufe; die Übung kostet weniger als einen Cent.

### Eigenen Stand bauen

Im Terminal des Dev Containers einen Zweig vom Tag `t05` der Musterlösung anlegen, den Filter ergänzen (Aufgabe auf der Übungsfolie von Termin 5) und das Image nach ghcr.io laden:

```bash
cd /workspaces/placefinder
git fetch upstream --tags                # tag t05 of the sample solution
git switch --create filter t05           # own branch from t05
# ... add the filter and its test ...
uv run pytest
../cloud-labs-local/02-container/publish-image.sh --tag t05
```

`publish-image.sh` baut den ausgecheckten Stand und lädt `placefinder:0.5.0` und `placefinder:t05` hoch; das Paket auf ghcr.io muss öffentlich sein. `upstream` einrichten: siehe [cloud-labs-local/00-setup](https://github.com/mf-iu/cloud-labs-local/tree/master/00-setup); Filter, Tests und Smoke-Test lokal: [cloud-labs-local/05-rest-api](https://github.com/mf-iu/cloud-labs-local/tree/master/05-rest-api). Ohne eigene Änderung lässt sich auch der Tag `t05` selbst ausrollen.

Der Dienst aus Teil 1 darf noch laufen. Wurde er gelöscht, legt `update-service.sh` ihn neu an; die Voraussetzungen von dort gelten (Default-VPC).

### Ausrollen und prüfen

```bash
cd /workspaces/cloud-labs-aws/03-container-service
./update-service.sh                      # about 10 minutes, ends with the smoke test
./smoke-test.sh                          # any time again; without URL: the service from t03
curl "<SERVICE_URL>/v1/places?min_population=1000000"   # the new filter
./smoke-test.sh http://localhost:8000    # the same checks against the local server
```

Die URL steht am Ende der Ausgabe von `update-service.sh` und in `../.state/t03.env` (`SERVICE_URL`). Den neuen Filter kennt der Smoke-Test nicht; ihn prüft `curl` von Hand.

**Digest statt Tag:** `update-service.sh` rollt `…/pf-<owner>-placefinder@sha256:…` aus, nicht `…:t05`. Ein Tag lässt sich später auf ein anderes Image setzen, der Digest benennt genau dieses eine. So bleibt nachvollziehbar, welche Version läuft, und jeder neue Task startet dasselbe Image.

**Canary-Deployment:** Express Mode startet die neue Version neben der alten, leitet 5 % der Anfragen auf sie um und wartet 3 Minuten (Bake Time). Danach bekommt sie 100 %, nach weiteren 3 Minuten stoppen die alten Tasks. Liegt der Anteil der 4xx- und 5xx-Antworten dabei über 1 %, rollt ein Alarm automatisch zurück. Deshalb startet der Smoke-Test erst nach dem Deployment: Seine absichtlichen 404- und 422-Anfragen würden sonst als Fehler zählen.

**Smoke-Test:** Die Ausgabe zeigt je Prüfung `OK` oder `FAIL` mit dem erwarteten Wert, am Ende ein Beispiel für Problem Details. Geprüft werden Medientyp `application/geo+json`, Länge vor Breite, Umkreis und Bounding Box um Erfurt, der Link `next` im Header `Link` und im Body, `ETag` mit `304 Not Modified`, Fehler als `application/problem+json`, CORS für die Karte auf `http://localhost:5173` und die Header `Deprecation` und `Sunset` der Version 0.

**Karte mit den Daten aus der Cloud:** In PlaceFinder `python3 -m http.server 5173 --directory frontend` starten und `http://localhost:5173/?api=<SERVICE_URL>` öffnen. Die API erlaubt diese Herkunft über CORS (`CORS_ORIGINS`).

### Aufräumen – gehört zur Übung

```bash
./destroy.sh
../tools/find-leftovers.sh
```

Wer das API-Gateway (Zusatz) angelegt hat, löscht es vorher mit `./destroy-api-gateway.sh` – es zeigt auf den Dienst. Erst wenn `find-leftovers.sh` nichts mehr meldet, ist die Übung fertig.

### Typische Probleme

- `Cannot pull … without login`: Das Image fehlt auf ghcr.io oder ist privat – siehe „Eigenen Stand bauen“.
- Smoke-Test meldet Version 0.1.x und viele `FAIL`: Der Dienst läuft noch mit dem Stand von Termin 3. Image mit `--tag t05` bauen, dann `./update-service.sh`.
- Deployment endet mit `ROLLBACK_SUCCESSFUL`: Die neue Version war nicht gesund (`/health`) oder lieferte zu viele Fehler. Logs in der ECS-Konsole unter *Clusters* → *default* → Dienst → *Logs*.
- `429` im Smoke-Test über das Gateway: kurz nach `rate-limit-test.sh` – einen Moment warten.

### Fragen zum Weiterdenken

- Welche Aufgaben übernimmt das API Gateway, die sonst in der Anwendung stünden (Rate Limits, Authentifizierung, Versionierung)?
- Warum antwortet das Gateway bei zu vielen Anfragen mit 429 und nicht mit 503?
- Wie kommt die Client-IP-Adresse durch Gateway und Load Balancer bis zur Anwendung (`X-Forwarded-For`)?
- Welche Antworten des Smoke-Tests dürfte ein CDN zwischenspeichern, und wie lange (`Cache-Control`)?
- Was müsste man ergänzen, damit nur angemeldete Nutzer Favoriten anlegen dürfen (JWT-Authorizer)?

## Zusatz: API Gateway mit Rate Limit

```bash
./create-api-gateway.sh         # HTTP API vor dem Dienst
./smoke-test.sh --gateway       # dieselben Prüfungen über das Gateway
./rate-limit-test.sh            # 60 Anfragen, je 10 gleichzeitig: 200 und 429
./destroy-api-gateway.sh
```

Das Skript legt eine HTTP API an, die alle Pfade (`ANY /{proxy+}`) an den Dienst weiterreicht. Die Stage begrenzt die Rate auf 10 Anfragen pro Sekunde mit Spitzen bis 20 (Token Bucket). Das Limit gilt für alle Clients zusammen; Limits je Kunde mit API-Keys und Nutzungsplänen bieten nur die REST APIs von API Gateway (3,50 USD je Million Aufrufe). Über dem Limit antwortet das Gateway mit `429 Too Many Requests`.

Das Gateway braucht den laufenden Dienst: erst `./update-service.sh`, am Ende `./destroy-api-gateway.sh` und `./destroy.sh`.

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Registry | Amazon ECR | Azure Container Registry (hier: ghcr.io) | Artifact Registry |
| Serverless Container | ECS Express Mode auf Fargate | Azure Container Apps | Cloud Run |
| Skalierung auf null | nein | ja | ja |
| Neue Version | Canary-Deployment mit automatischem Rollback | neue Revision | neue Revision, Traffic Splitting |
| API-Gateway | API Gateway (HTTP API) | API Management (Consumption) | API Gateway |
| Rate Limit | Throttling je Stage oder Route, für alle Clients zusammen | Richtlinie `rate-limit` je Abonnement | Kontingent je Projekt des API-Keys |
| Schlüssel | API-Keys nur bei REST APIs | Abonnementschlüssel im Header `Ocp-Apim-Subscription-Key` | API-Key, hier im Header `x-api-key` |
