# 06 – Infrastruktur als Code: base und service

**Ziel:** Die Infrastruktur der Zwischenpräsentation entsteht beim neuen Anbieter reproduzierbar aus OpenTofu-Code mit Remote State – in zwei Teilen:

- **`base`** – VPC aus Termin 4, S3-Bucket aus Termin 7, IAM-Rollen für ECS Express Mode. Entsteht einmal in Termin 8 und bleibt bis zum Kursende; kostet praktisch nichts.
- **`service`** – PlaceFinder auf ECS Express Mode, optional RDS for PostgreSQL. Liest die Ausgaben von `base` und wird im Termin angelegt und wieder gelöscht.

Die Function, der Data Lake, ML und das Abschlussprojekt bauen später ebenfalls auf `base` auf. Ein Workflow im eigenen Fork rollt neue Images ohne gespeicherte Zugangsschlüssel aus. Lokal gehören dazu OpenTofu mit Docker, die Pipeline im eigenen Fork und die Beobachtbarkeit mit Grafana: [cloud-labs-local/08-iac-and-operations](https://github.com/mf-iu/cloud-labs-local/tree/master/08-iac-and-operations).

| Ordner oder Datei | Aufgabe |
|---|---|
| `bootstrap-state.sh`, `destroy-state.sh` | S3-Bucket für den Remote State anlegen bzw. am Kursende löschen |
| `base/` | VPC aus Termin 4, S3-Bucket aus Termin 7, IAM-Rollen für ECS Express Mode; bleibt bis zum Kursende |
| `service/` | PlaceFinder auf ECS Express Mode, optional RDS for PostgreSQL; im Termin anlegen und löschen |
| `github-oidc/` | Vertrauensstellung für GitHub Actions: OIDC-Anbieter und Rolle, die nur der eigene Fork übernehmen darf |
| `deploy.example.yml` | Workflow für den eigenen Fork: Image aus der Pipeline per Digest ausrollen, Smoke-Test |

**Kosten:** `base` kostet praktisch nichts und darf bis zum Kursende bestehen bleiben. `service`: Dienst mit Load Balancer wie in Termin 3 ca. 1 USD pro Tag, mit Datenbank zusätzlich ca. 0,5 USD pro Tag, aus dem Guthaben. State-Bucket und IAM sind praktisch kostenlos. **Nach dem Test `destroy` ausführen.**

## Voraussetzungen

- Dev Container dieses Repositorys mit OpenTofu ab 1.10 (`../cloud-labs-local/tools/check-tools.sh`)
- AWS-Konto beim neuen Anbieter eingerichtet (Schritt `01-account` mit dem [Anbieterwechsel](../01-account/README.md#anbieterwechsel)), `aws login` aktiv, `config.env` ausgefüllt
- Image `$PLACEFINDER_IMAGE:t08` öffentlich auf ghcr.io: `../cloud-labs-local/02-container/publish-image.sh --tag t08` oder die Pipeline des Forks, danach das Paket auf GitHub öffentlich machen

## 1. Remote State einrichten (einmalig)

```bash
cd /workspaces/cloud-labs-aws
06-infrastructure-as-code/bootstrap-state.sh
```

Das Skript legt einen versionierten, privaten Bucket `pf-<owner>-<suffix>-tfstate` an und schreibt `.state/backend.hcl`. Gesperrt wird der State über eine Lock-Datei im Bucket (`use_lockfile`); eine DynamoDB-Tabelle ist nicht mehr nötig. Den Bucket legt die CLI an, weil OpenTofu seinen State-Speicher nicht verwalten kann, bevor es ihn gibt (Henne-Ei-Problem).

## 2. base anlegen (einmalig, bleibt bis zum Kursende)

```bash
tools/tofu.sh 06-infrastructure-as-code/base plan      # beim ersten Aufruf mit init
tools/tofu.sh 06-infrastructure-as-code/base apply
tools/tofu.sh 06-infrastructure-as-code/base output
```

`tools/tofu.sh` setzt die Variablen `prefix`, `owner`, `suffix`, `region` und `placefinder_image` aus `config.env` und verwendet für jeden Ordner einen eigenen Schlüssel im State-Bucket, z. B. `06-infrastructure-as-code/base/terraform.tfstate`. Dazu kommt `backend` mit den Einstellungen aus `.state/backend.hcl`: Damit liest `service` die Ausgaben von `base` (`terraform_remote_state`).

| Datei | Inhalt |
|---|---|
| `base/network.tf` | VPC `10.20.0.0/16` mit öffentlichen, Anwendungs- und Datenbank-Subnetzen in zwei Zonen wie in Termin 4 |
| `base/storage.tf` | privater S3-Bucket mit CORS und Lebenszyklusregeln wie in Termin 7 |
| `base/roles.tf` | Execution Role und Infrastructure Role für ECS Express Mode |
| `base/outputs.tf` | VPC, Subnetze, Bucket und Rollen für `service` und spätere Konfigurationen |

## 3. service anlegen, prüfen, löschen (im Termin)

```bash
tools/tofu.sh 06-infrastructure-as-code/service plan
tools/tofu.sh 06-infrastructure-as-code/service apply     # ca. 5 Minuten
tools/tofu.sh 06-infrastructure-as-code/service output
curl "$(tools/tofu.sh 06-infrastructure-as-code/service output -raw service_url)/health"
tools/tofu.sh 06-infrastructure-as-code/service destroy   # am Ende des Termins
```

`service/base.tf` liest die Ausgaben von `base` aus dessen State (`terraform_remote_state`): Netz, Subnetze, Speicher und was der Dienst sonst braucht. `service` legt also nichts doppelt an und kann jederzeit gelöscht werden, ohne `base` anzutasten.

| Datei | Inhalt |
|---|---|
| `service/base.tf` | liest die Ausgaben von `base` (`terraform_remote_state`) |
| `service/service.tf` | PlaceFinder auf ECS Express Mode in den öffentlichen Subnetzen von `base` |
| `service/database.tf` | optional: RDS for PostgreSQL 18 in den Datenbank-Subnetzen, Passwort in Secrets Manager |
| `service/outputs.tf` | URL und ARN des Dienstes, Datenbank |

**Warum die öffentlichen Subnetze?** Mit öffentlichen Subnetzen legt Express Mode einen Load Balancer mit öffentlicher Adresse an und gibt den Tasks öffentliche IP-Adressen; so laden sie das Image von ghcr.io. In den Anwendungs-Subnetzen bräuchten sie dafür ein NAT-Gateway (ca. 1 USD pro Tag). Von außen erreichbar ist trotzdem nur der Load Balancer: Die Security Group der Tasks lässt nur ihn herein.

### Mit Datenbank

```bash
tools/tofu.sh 06-infrastructure-as-code/service apply -var enable_database=true    # ca. 10 Minuten mehr
curl "$(tools/tofu.sh 06-infrastructure-as-code/service output -raw service_url)/health"   # "places": 34000 und mehr
```

Anders als in Termin 6 liegt die Datenbank in den Datenbank-Subnetzen ohne öffentliche Adresse; die Security Group lässt nur PostgreSQL aus den Subnetzen des Dienstes zu. Vom eigenen Rechner aus ist sie nicht erreichbar, `load-cities.sh` geht also nicht. Stattdessen lädt PlaceFinder beim ersten Start die Orte aus dem Image (`DATABASE_INIT=true`).

Das Passwort legt RDS selbst an und verwaltet es in Secrets Manager (`manage_master_user_password`); es steht weder im Code noch im State. ECS liest den Schlüssel `password` des Secrets und gibt ihn als `PGPASSWORD` an PlaceFinder; die Verbindungszeichenkette `DATABASE_URL` enthält kein Passwort.

## 4. Ausrollen aus der Pipeline, ohne Schlüssel

```bash
tools/tofu.sh 06-infrastructure-as-code/github-oidc apply -var github_repository=<github-user>/placefinder
tools/tofu.sh 06-infrastructure-as-code/github-oidc output
```

Die Konfiguration legt den OIDC-Identitätsanbieter für `token.actions.githubusercontent.com` und eine Rolle an, die nur Workflows auf dem Branch `master` des genannten Repositorys übernehmen dürfen. Die Rolle darf Express-Mode-Dienste aktualisieren und dafür die beiden Rollen aus `base` weitergeben – sonst nichts. Gibt es den OIDC-Anbieter im Konto schon, mit `-var create_oidc_provider=false` arbeiten.

Im eigenen PlaceFinder-Fork:

1. `deploy.example.yml` als `.github/workflows/deploy.yml` übernehmen, committen, pushen.
2. Repository-Variablen anlegen (*Settings* → *Secrets and variables* → *Actions* → *Variables*): `AWS_ROLE_ARN` und `AWS_REGION` aus `github-oidc`, `SERVICE_ARN` und `SERVICE_URL` (Ausgabe `service_url`) aus `service`.
3. Eine kleine Änderung pushen. Nach der grünen Pipeline startet `deploy`: Image per Digest ausrollen (Canary, ca. 10 Minuten), dann der Smoke-Test aus Termin 5.

**Pipeline und OpenTofu:** `image_tag` bestimmt nur das erste Image. Danach rollt die Pipeline aus; `ignore_changes` in `service.tf` verhindert, dass das nächste `apply` auf `image_tag` zurücksetzt. Jede Eigenschaft gehört genau einem Werkzeug.

## 5. Logs und Metriken beim Anbieter

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/ecs --query 'logGroups[].logGroupName'
aws logs tail <log-gruppe> --since 15m --follow
```

In der Konsole: *CloudWatch* → *Metrics* → *ApplicationELB* (Anfragen, `TargetResponseTime`, `HTTPCode_Target_5XX_Count`) und *ECS* (CPU, Speicher). Das ist RED für den Dienst – ohne eine Zeile Code, aber nur an der Grenze des Load Balancers; die Spans in der Anwendung liefert erst OpenTelemetry.

## Ausprobieren

- Eine Einstellung ändern (z. B. `-var max_tasks=3`) und den Plan lesen: Was ändert sich in place (`~`), was wird ersetzt (`-/+`)?
- In der Konsole etwas von Hand ändern, z. B. die Lebenszyklusregel des Buckets löschen, und mit `plan` die Abweichung finden (Drift).
- `destroy` und `apply` hintereinander: Ist alles wieder gleich? Was hat sich geändert (Adressen, Namen)?
- `tools/tofu.sh 06-infrastructure-as-code/base state list` und `state show aws_vpc.main`; `tools/tofu.sh 06-infrastructure-as-code/service state show data.terraform_remote_state.base`
- `base` ändern und `service` neu planen: Was sieht `service` von der Änderung, ohne dass sich sein eigener Code ändert?

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No remote state yet` | `bootstrap-state.sh` fehlt | `06-infrastructure-as-code/bootstrap-state.sh` |
| `Error acquiring the state lock` | Ein anderer Lauf hält die Sperre oder ist abgebrochen. | warten; nach einem Abbruch `tofu force-unlock <id>` mit der ID aus der Meldung |
| Dienst startet nicht, Image nicht gefunden | `:t08` fehlt auf ghcr.io oder ist privat | `../cloud-labs-local/02-container/publish-image.sh --tag t08`, Paket öffentlich machen |
| `/health` antwortet erst nach einer Minute | Beim ersten Start mit Datenbank lädt PlaceFinder die Orte. | warten; Logs zeigen `Loaded … places` |
| Workflow: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Repository oder Branch passt nicht zur Rolle | `github_repository` genau wie auf GitHub, Branch `master` |
| Workflow `deploy` startet nicht | `deploy.yml` liegt nicht auf `master` oder der Workflow `ci` heißt anders | Datei auf `master`, `workflows: [ci]` |
| `service`: `Unable to find remote state` oder fehlende Ausgaben von `base` | `base` ist noch nicht angelegt oder gelöscht | `tools/tofu.sh 06-infrastructure-as-code/base apply` |

## Aufräumen

Nach jedem Termin:

```bash
tools/tofu.sh 06-infrastructure-as-code/service destroy
```

Am Kursende, nach den Konfigurationen der späteren Termine:

```bash
tools/tofu.sh 06-infrastructure-as-code/github-oidc destroy -var github_repository=<github-user>/placefinder
tools/tofu.sh 06-infrastructure-as-code/base destroy
06-infrastructure-as-code/destroy-state.sh      # nach allen anderen destroy-Aufrufen
tools/find-leftovers.sh
```

## Fragen zum Weiterdenken

- Was steht im State, und warum gehört er nicht ins Git-Repository? Wie schützt dieser Bucket ihn?
- Warum ist OIDC-Federation sicherer als ein Access Key in den GitHub-Secrets?
- Welche Teile der Konfiguration sind anbieterspezifisch, welche ließen sich als Modul für alle drei Anbieter schreiben?
- Die Pipeline rollt aus, OpenTofu ignoriert das Image. Was ginge verloren, wenn OpenTofu auch das Image verwaltete – und was mit GitOps?
- Welches SLO würden Sie für PlaceFinder festlegen, und welche Metrik misst es?
- Was gehört in `base`, was in `service`? Woran erkennt man, dass eine Ressource zwischen den Terminen bestehen bleiben darf?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| State-Backend | S3 mit Lock-Datei | Storage Account (Blob Lease) | Cloud Storage |
| Datenbank im privaten Netz | RDS in Subnetzen ohne Route ins Internet | Flexible Server mit delegiertem Subnetz und privater DNS-Zone | Cloud SQL mit privater IP über Private Services Access |
| Datenbank-Passwort | Secrets Manager, von RDS verwaltet | Secret der Container App | Secret Manager |
| Ausrollen ohne Schlüssel | IAM-OIDC-Anbieter + Rolle | Managed Identity + Federated Credential | Workload Identity Federation |
| Native IaC | CloudFormation, CDK | Bicep | Infrastructure Manager |
| Logs und Metriken | CloudWatch, X-Ray | Azure Monitor, Application Insights | Cloud Logging, Cloud Monitoring, Cloud Trace |
