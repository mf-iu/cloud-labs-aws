# Cloud-Übungen: AWS

Skripte für den praktischen Teil des Kurses „Cloud Computing – Konzepte und Praxis für die Softwareentwicklung“ bei Amazon Web Services (AWS). Die Ordner enthalten nur, was beim Anbieter läuft; alles, was ohne Cloud-Konto geht, steht in [cloud-labs-local](https://github.com/mf-iu/cloud-labs-local). Die Gegenstücke für die anderen Anbieter liegen in `cloud-labs-azure` und `cloud-labs-gcp`; Aufbau und Ordnernamen sind dort gleich.

Jeder Teilnehmer arbeitet in der ersten Kurshälfte (Termine 1–7) mit einem Anbieter und wechselt nach der Zwischenpräsentation zu einem anderen (Termine 8–12). Wer AWS erst ab Termin 8 nutzt, richtet das Konto mit `01-account` ein und arbeitet dann mit `06-infrastructure-as-code` weiter.

## Voraussetzungen

- [cloud-labs-local](https://github.com/mf-iu/cloud-labs-local) und der eigene Fork von PlaceFinder **neben diesem Repository** in `~/kurs`, eingerichtet nach [cloud-labs-local/00-setup](https://github.com/mf-iu/cloud-labs-local/tree/master/00-setup). Die Skripte hier laden die gemeinsame Bibliothek von dort (`lib/common.sh`), der Dev Container baut dessen Dockerfile.
- Ein AWS-Konto im kostenlosen Plan (Free Plan) – Einrichtung in [01-account](01-account/README.md)

## Arbeitsumgebung: Dev Container

`code ~/kurs/cloud-labs-aws` öffnen und „Reopen in Container“ wählen. Der Dev Container baut das Dockerfile aus `cloud-labs-local/.devcontainer/` mit allen Werkzeugen der Übungen und ergänzt die CLI von AWS; die Anmeldung liegt in WSL und übersteht einen Neubau. Unter `/workspaces` sind alle Repositories da: dieses, `cloud-labs-local` und `placefinder`. Beim Anlegen zeigen `../cloud-labs-local/tools/check-tools.sh` und `01-account/check-cli.sh --tools-only` die Versionen. Einzelheiten – Terminal, Ports, Neubau – stehen in [cloud-labs-local/00-setup](https://github.com/mf-iu/cloud-labs-local/tree/master/00-setup).

## Einrichtung

Im Terminal des Dev Containers, nachdem `config.env` in `cloud-labs-local` ausgefüllt ist:

```bash
cp config.example.env config.env      # Kürzel, Region, Budget usw. eintragen
01-account/check-cli.sh               # prüft CLI, Nachbarordner, Anmeldung und Einstellungen
```

`config.env` und der Ordner `.state/` gehören nur auf den eigenen Rechner und sind in `.gitignore` eingetragen. In `.state/` merken sich die Skripte die IDs der angelegten Ressourcen, damit die Aufräumskripte sie wiederfinden, außerdem Zugangsdaten der Übungsdatenbank. Downloads wie GeoNames und die Kacheln liegen in `cloud-labs-local/.state/data/`.

## Übersicht

Die Ordner folgen dem Inhalt; die Spalte *Termin* nennt, wann sie dran sind. Die lokalen Schritte desselben Termins stehen in der Übersicht von `cloud-labs-local`.

| Termin | Ordner | Inhalt | Werkzeug |
|---|---|---|---|
| 1 | [01-account](01-account/README.md) | Konto absichern, CLI-Anmeldung, Budget-Alarm; Anbieterwechsel | AWS CLI |
| 2 | [02-vm](02-vm/README.md) | PlaceFinder v0 per cloud-init auf einer EC2-VM (IaaS) | AWS CLI |
| 3, 5 | [03-container-service](03-container-service/README.md) | Image in Amazon ECR, Betrieb mit ECS Express Mode (Serverless Container); neue Version per Digest (Canary), Smoke-Test; Zusatz API Gateway mit Rate Limit | AWS CLI, curl |
| 4 | [04-network](04-network/README.md) | VPC mit öffentlichen und privaten Subnetzen, Security Groups; Zusatz Test-VMs mit Bastion-Host und NAT-Gateway | AWS CLI |
| 6 (Zusatz), 7 | [05-storage](05-storage/README.md) | S3-Bucket mit Pre-Signed URLs, Range Requests, CORS und Kartenkacheln; Zusatz RDS for PostgreSQL mit PostGIS | AWS CLI, psql |
| 8 | [06-infrastructure-as-code](06-infrastructure-as-code/README.md) | `base` (VPC, Bucket, Rollen) und `service` (ECS Express Mode, RDS im privaten Subnetz) als Code, Remote State in S3; Ausrollen aus GitHub Actions ohne Schlüssel (OIDC) | OpenTofu, GitHub Actions |
| 9 | [t09-serverless](t09-serverless/README.md) | Täglicher GeoNames-Abgleich als Lambda-Function mit EventBridge Scheduler | OpenTofu, Python |
| 10 | [t10-datenanalyse](t10-datenanalyse/README.md) | GeoParquet im Data Lake, Abfragen mit DuckDB und Athena, Overture Maps | OpenTofu, DuckDB |
| 11 | [t11-ml](t11-ml/README.md) | Modell-Endpunkt `/estimate`, MLflow-Artefakte in S3 | OpenTofu |

Termin 12 (Abschluss) hat keinen eigenen Ordner; das Abschlussprojekt baut auf `06-infrastructure-as-code/base` auf. Die Ordner `t09` bis `t11` werden noch nach diesem Schema geordnet.

## Ablauf jeder Übung

1. Ressourcen anlegen: `create-….sh`, `deploy.sh` bzw. `tools/tofu.sh <ordner> apply`
2. Ausprobieren: Testbefehle aus der Anleitung des Termins
3. **Aufräumen:** `destroy-….sh` bzw. `tools/tofu.sh <ordner> destroy`
4. Kontrolle: `tools/find-leftovers.sh` listet übrig gebliebene Ressourcen auf

Die Skripte fragen vor dem Löschen nach. Mit `ASSUME_YES=1` vor dem Befehl entfällt die Rückfrage.

**Namen und Tags:** Alle Ressourcen heißen `<prefix>-<owner>-…`, z. B. `pf-mf-t02-vm`, und tragen die Tags `course=cloud-computing` und `lab=<termin>`. So bleiben die Ressourcen mehrerer Teilnehmer in einem Konto unterscheidbar.

**Ab Termin 8 mit OpenTofu:** `06-infrastructure-as-code/bootstrap-state.sh` legt einmalig den S3-Bucket für den Remote State an. Danach läuft jede Konfiguration über `tools/tofu.sh`, das den Backend-Zugang und die gemeinsamen Variablen aus `config.env` setzt:

```bash
tools/tofu.sh 06-infrastructure-as-code/base apply       # once, stays until the end of the course
tools/tofu.sh 06-infrastructure-as-code/service apply    # in the session
tools/tofu.sh 06-infrastructure-as-code/service destroy  # at the end of the session
```

## Kostenregeln

- Gleich am ersten Tag den Budget-Alarm einrichten (`01-account/create-budget.sh`).
- Nach jeder Übung alles abbauen; nur `06-infrastructure-as-code/base` bleibt bis zum Kursende. Teuer im Dauerbetrieb sind vor allem NAT-Gateways, Load Balancer (auch der von ECS Express Mode), RDS-Instanzen und öffentliche IPv4-Adressen.
- Nicht auf den kostenpflichtigen Plan umstellen. Im Free Plan zahlt AWS aus dem Guthaben; ist es aufgebraucht oder sind sechs Monate um, wird das Konto geschlossen, aber nichts berechnet.
- Preisangaben in den Anleitungen sind Richtwerte für die Region Frankfurt (Stand Oktober 2026) und dienen nur der Orientierung.

## Daten und Lizenzen

- GeoNames (`cities15000`, tägliche Änderungsdateien): CC BY 4.0, Namensnennung „GeoNames“
- OpenStreetMap und Overture Maps: ODbL bzw. CDLA Permissive 2.0, je nach Thema
- Geodaten werden nie eingecheckt, sondern von den Skripten geladen.

## Konventionen

Anleitungen auf Deutsch, Skripte, Kommentare und Commit-Messages auf Englisch. Die Shell-Skripte sind mit ShellCheck geprüft (`shellcheck */*.sh`; `cloud-labs-local` muss daneben liegen), die OpenTofu-Dateien mit `tofu fmt`, die Python-Dateien mit Ruff (`ruff check`, `ruff format`).
