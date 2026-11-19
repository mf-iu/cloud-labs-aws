# 07 – Serverless: der tägliche GeoNames-Abgleich als Lambda-Function

**Ziel:** Eine AWS-Lambda-Function holt jeden Morgen die Änderungen des Vortags von GeoNames, filtert sie auf die Orte von `cities15000` und legt sie im S3-Bucket von `base` ab. EventBridge Scheduler startet sie täglich um 6:30 Uhr deutscher Zeit. Der Kern ist `geonames_sync.py` aus `cloud-labs-local`; hier kommen nur der Handler, das Paket und die Infrastruktur dazu.

**Baut auf:** [06-infrastructure-as-code](../06-infrastructure-as-code/README.md) (`base` mit dem Bucket); lokal [cloud-labs-local/09-serverless](https://github.com/mf-iu/cloud-labs-local/tree/master/09-serverless) · **Termin:** 9

**Kosten:** im Freikontingent: 1 Million Aufrufe und 400.000 GB-Sekunden im Monat für Lambda, 14 Millionen Aufrufe für EventBridge Scheduler; ein Lauf dauert wenige Sekunden. Zusatz: SQS und ein CloudWatch-Alarm kosten praktisch nichts (10 Alarme im Monat frei).

| Datei | Aufgabe |
|---|---|
| `function/handler.py` | Lambda-Handler: übergibt `geonames_sync.run()` eine Funktion, die mit boto3 ein Objekt in den Bucket schreibt |
| `function/requirements.txt` | `pg8000` für die optionale Datenbank; boto3 bringt die Runtime mit |
| `package.sh` | baut `build/`: Handler, `geonames_sync.py` aus `cloud-labs-local/09-serverless` und `pg8000` |
| `infra/` | OpenTofu: Rolle, Log-Gruppe (7 Tage), Lambda, Wiederholungen, Zeitplan; Zusatz Dead-Letter-Queue mit Alarm |
| `invoke.sh` | von Hand aufrufen: Ende des Logs und Ergebnis zeigen; mit `--async` wie der Zeitplan |

## Voraussetzungen

- `base` steht: `tools/tofu.sh 06-infrastructure-as-code/base output bucket` zeigt den Bucket.
- Schritt 1 aus `cloud-labs-local/09-serverless` ist bekannt (den Kern lokal ausführen).
- `aws login` ist aktiv; `01-account/check-cli.sh` prüft das.

## Übung im Termin

```bash
cd /workspaces/cloud-labs-aws
(cd ../cloud-labs-local/09-serverless && python3 geonames_sync.py --out out)   # 1. lokal
07-serverless/package.sh                                   # 2. Paket bauen
tools/tofu.sh 07-serverless/infra apply                    #    Function und Zeitplan
07-serverless/invoke.sh                                    # 3. auslösen: gestern
aws s3 ls --recursive "s3://$(tools/tofu.sh 07-serverless/infra output -raw bucket)/geonames/"
07-serverless/invoke.sh 2026-11-17                         # 4. ein Tag, zweimal: gleiches Ergebnis
07-serverless/invoke.sh 2026-11-17
tools/tofu.sh 07-serverless/infra destroy                  # 5. abbauen
tools/find-leftovers.sh                                    #    nur noch base
```

**Paket:** `package.sh` kopiert den Handler und `geonames_sync.py` aus dem Nachbarordner `cloud-labs-local` nach `07-serverless/build/` und installiert `pg8000` für die Lambda-Runtime (`--platform manylinux2014_x86_64 --python-version 3.12`). OpenTofu packt den Ordner als ZIP (`archive_file`); ändert sich der Code, ändert sich der Hash, und `apply` lädt ein neues Paket hoch.

**Handler:** Alles außerhalb von `lambda_handler` läuft einmal je Umgebung (Init): der S3-Client und der Name des Buckets. `lambda_handler` läuft einmal je Ereignis und ruft `run(store, day)`; ein leeres Ereignis vom Zeitplan heißt „gestern“.

**Kaltstart:** Beim ersten Aufruf nach dem Ausrollen steht im Log von `invoke.sh` die Zeile `REPORT … Init Duration: … ms`. Der zweite Aufruf kurz danach ist warm und hat keine Init-Zeile. Bei einem Lauf am Tag ist jeder Start kalt; das stört hier nicht.

**Idempotent:** Derselbe Tag ergibt dieselben drei Objekte unter `geonames/changes/<Tag>/`, `summary.json` hat denselben Inhalt.

## Die Infrastruktur

| Datei | Inhalt |
|---|---|
| `infra/base.tf` | liest den Bucket aus dem State von `base` (`terraform_remote_state`) |
| `infra/main.tf` | Ausführungsrolle (Logs, `s3:PutObject` nur unter `geonames/`), Log-Gruppe, Lambda, Wiederholungen, Rolle und Zeitplan von EventBridge Scheduler |
| `infra/dead_letter.tf` | Zusatz: SQS-Queue, Recht zum Senden, Alarm, optional E-Mail über SNS |
| `infra/outputs.tf` | Name der Function, Bucket, Log-Gruppe, Adresse der Dead-Letter-Queue |

**Wer wiederholt?** EventBridge Scheduler übergibt das Ereignis asynchron an Lambda. Seine eigenen Wiederholungen (`retry_policy`) greifen nur, wenn die Übergabe scheitert, etwa bei Drosselung. Scheitert der Lauf selbst, etwa weil GeoNames die Datei noch nicht veröffentlicht hat, wiederholt Lambda: zweimal, nach etwa einer und nach zwei weiteren Minuten (`aws_lambda_function_event_invoke_config`). Ein synchroner Aufruf mit `invoke.sh` wird nicht wiederholt; der Aufrufer sieht den Fehler sofort.

## Zusatz: Dead-Letter-Queue mit Alarm

```bash
tools/tofu.sh 07-serverless/infra apply -var dead_letter=true -var "alert_email=du@example.com"
07-serverless/invoke.sh --async 2099-01-01                 # einen Tag, den es nicht gibt
# nach etwa 3 Minuten: zwei Wiederholungen, dann die Queue; Alarm nach höchstens 5 Minuten
queue=$(tools/tofu.sh 07-serverless/infra output -raw dead_letter_queue)
aws sqs receive-message --queue-url "$queue" --query 'Messages[0].Body' --output text | jq .
aws cloudwatch describe-alarms --state-value ALARM --query 'MetricAlarms[].AlarmName'   # …-geonames-dlq-not-empty
```

Mit `dead_letter=true` schickt Lambda ein Ereignis, das auch nach den Wiederholungen scheitert, als Nachricht an eine SQS-Queue (Ziel für Fehlschläge, `on_failure`). Die Nachricht enthält das ursprüngliche Ereignis, die Fehlermeldung und die Zahl der Versuche; sie bleibt 14 Tage. Ein CloudWatch-Alarm schlägt an, sobald eine Nachricht wartet (`ApproximateNumberOfMessagesVisible > 0`), und schickt mit `alert_email` eine E-Mail über SNS; AWS fragt vorher per E-Mail nach einer Bestätigung. Ohne die Variable legt `count = 0` keine dieser Ressourcen an.

Die Dead-Letter-Queue macht dauerhafte Fehler sichtbar, statt sie zu verlieren. Nach der Ursache sucht man in der Log-Gruppe: `aws logs tail /aws/lambda/<name> --since 1h`. Das ist auch der Kern von Thema 2 des Abschlussprojekts.

## Zusatz: mit Datenbank

```bash
tools/tofu.sh 07-serverless/infra apply -var "database_url=postgresql://…?sslmode=require"
```

Ist `DATABASE_URL` gesetzt, spielt der Kern die Änderungen per Upsert in die Tabelle `places` ein. Die Datenbank aus `06-infrastructure-as-code/service` liegt im privaten Netz und ist für eine Lambda ohne VPC-Anbindung nicht erreichbar; mit der Datenbank aus `05-storage` (Termin 6) geht es, wenn ihre Security Group den Zugriff vorübergehend erlaubt. Lambda hat ohne VPC keine feste Absenderadresse. Sauberer wäre eine Lambda im VPC der Datenbank; für den Download bräuchte sie dann aber ein NAT-Gateway.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No output bucket from base` | `base` fehlt oder ist abgebaut. | `tools/tofu.sh 06-infrastructure-as-code/base apply` |
| `Not found: …/09-serverless/geonames_sync.py` | `cloud-labs-local` ist veraltet. | `git -C ../cloud-labs-local pull` |
| `archive_file`: `no such file or directory` | Das Paket fehlt. | `07-serverless/package.sh` |
| `… is not (yet) published` | GeoNames hat die Datei des Tages noch nicht veröffentlicht. | früheren Tag angeben |
| `AccessDenied` bei `PutObject` | `base` wurde neu angelegt, die Rolle zeigt auf den alten Bucket. | `tools/tofu.sh 07-serverless/infra apply` |
| `Task timed out after 120.00 seconds` | GeoNames antwortet langsam. | erneut auslösen; `timeout` in `main.tf` erhöhen |

## Aufräumen

```bash
tools/tofu.sh 07-serverless/infra destroy
tools/find-leftovers.sh
```

Die Objekte unter `geonames/` bleiben im Bucket von `base`; sie kosten praktisch nichts und verschwinden mit `base` am Kursende.

## Fragen zum Weiterdenken

- Was passiert, wenn GeoNames die Datei um 6:30 Uhr noch nicht veröffentlicht hat? Was erledigen die Wiederholungen, was die Dead-Letter-Queue?
- Warum muss die Function idempotent sein, obwohl sie nur einmal am Tag läuft?
- Ab wie vielen Aufrufen wäre ein dauerhaft laufender Container günstiger?
- Eine zweite Function soll auf neue Objekte im Bucket reagieren (S3-Ereignis → Lambda). Warum muss sie auf ein anderes Präfix hören als das, in das sie schreibt?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Function | Lambda | Azure Functions (Flex Consumption) | Cloud Run functions |
| Zeitsteuerung | EventBridge Scheduler | Timer-Trigger im Code | Cloud Scheduler |
| Wiederholungen | Lambda, asynchron zweimal | Retry-Strategie im Code | Cloud Scheduler |
| Zusatz: Dead-Letter | SQS als Ziel für Fehlschläge | Poison Queue einer Storage Queue | Dead-Letter-Topic von Pub/Sub |
| Lokal | `09-serverless`, SAM CLI | `09-serverless`, Functions Core Tools | `09-serverless`, Functions Framework |
