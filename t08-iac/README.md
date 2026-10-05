# T08 – Infrastruktur als Code mit OpenTofu

**Ziel:** Die Infrastruktur der Zwischenpräsentation entsteht reproduzierbar aus Code: Netz, Bucket, Container-Registry und PlaceFinder-Dienst, optional mit Datenbank. Der State liegt versioniert in S3. Außerdem darf eine GitHub-Actions-Pipeline ohne gespeicherte Zugangsschlüssel Images bauen und ausrollen (OIDC-Federation).

**Kosten:** Wie Termin 3 (Dienst mit Load Balancer ca. 1 USD pro Tag), mit Datenbank zusätzlich ca. 0,5 USD pro Tag. State-Bucket und IAM sind praktisch kostenlos. Nach dem Test `destroy` ausführen.

## Voraussetzungen

- OpenTofu ab 1.10 (`tofu version`)
- `aws login` aktiv, `config.env` ausgefüllt
- Image `$PLACEFINDER_IMAGE:t07` (oder ein anderer Tag über `-var image_tag=…`)

## 1. Remote State einrichten (einmalig)

```bash
./bootstrap-state.sh
```

Das Skript legt einen versionierten, privaten Bucket `pf-<owner>-<suffix>-tfstate` an und schreibt `../.state/backend.hcl`. Gesperrt wird der State über eine Lock-Datei im Bucket (`use_lockfile`), eine DynamoDB-Tabelle ist nicht mehr nötig. Der Bucket wird mit der CLI angelegt, weil OpenTofu seinen eigenen State-Speicher nicht verwalten kann, bevor es ihn gibt (Henne-Ei-Problem).

## 2. Infrastruktur ausrollen

```bash
cd ..
tools/tofu.sh t08-iac/infra plan      # beim ersten Aufruf mit init
tools/tofu.sh t08-iac/infra apply
tools/tofu.sh t08-iac/infra output
```

`tools/tofu.sh` setzt die Variablen `prefix`, `owner`, `suffix`, `region`, `placefinder_image` und `admin_cidrs` (eigene IP-Adresse) aus `config.env` und verwendet für jeden Ordner einen eigenen State-Schlüssel.

| Datei | Inhalt |
|---|---|
| `infra/network.tf` | VPC mit öffentlichen, Anwendungs- und Datenbank-Subnetzen wie in Termin 4 |
| `infra/storage.tf` | S3-Bucket für Daten, ECR-Repository mit Lebenszyklusregel |
| `infra/service.tf` | IAM-Rollen und PlaceFinder auf ECS Express Mode |
| `infra/database.tf` | optional: RDS for PostgreSQL (`-var enable_database=true`) |
| `infra/outputs.tf` | URL, Bucket, Repository, Dienst-ARN, Verbindungszeichenkette |

Mit Datenbank:

```bash
tools/tofu.sh t08-iac/infra apply -var enable_database=true
tools/tofu.sh t08-iac/infra output -raw database_url
```

Die Datenbank ist wie in Termin 6 nur von der eigenen IP-Adresse aus erreichbar. Den Dienst mit der Datenbank zu verbinden, ist Teil der Übung: Dienst und Datenbank müssen dazu in dieselbe VPC (`network_configuration` des Dienstes mit den Subnetzen dieser VPC, Security Group `sg-db` mit Zugriff von der Security Group des Dienstes), und die Verbindungszeichenkette gehört in den Secrets Manager statt in eine Umgebungsvariable.

### Ausprobieren

- Eine Einstellung ändern (z. B. `max_task_count`) und `plan` lesen: Was ändert sich, was wird ersetzt?
- In der Konsole etwas von Hand ändern und mit `plan` die Abweichung (Drift) finden.
- `destroy` und `apply` hintereinander ausführen: Ist alles wieder gleich?

## 3. GitHub Actions ohne Schlüssel (OIDC)

```bash
tools/tofu.sh t08-iac/github-oidc apply -var github_repository=<github-user>/placefinder
tools/tofu.sh t08-iac/github-oidc output
```

Die Konfiguration legt den OIDC-Identitätsanbieter für `token.actions.githubusercontent.com` und eine Rolle an, die nur Workflows auf dem Branch `master` des genannten Repositorys übernehmen dürfen. Die Rolle darf Images in die eigenen ECR-Repositories schieben und Express-Mode-Dienste aktualisieren. Gibt es den OIDC-Anbieter im Konto schon, mit `-var create_oidc_provider=false` arbeiten.

In den eigenen PlaceFinder-Fork übernehmen:

1. `deploy.example.yml` als `.github/workflows/deploy.yml`
2. Repository-Variablen (*Settings* → *Secrets and variables* → *Actions* → *Variables*): `AWS_ROLE_ARN`, `AWS_REGION` aus `github-oidc`, `ECR_REPOSITORY_URL` und `SERVICE_ARN` aus `infra`

Rollt die Pipeline ein neues Image aus, weicht der Dienst von der OpenTofu-Konfiguration ab; das nächste `apply` würde wieder `image_tag` setzen. Für den Kurs ist das ein gutes Beispiel für Drift – in echten Projekten übernimmt entweder die Pipeline oder OpenTofu das Image, nicht beide.

## Aufräumen

```bash
tools/tofu.sh t08-iac/github-oidc destroy -var github_repository=<github-user>/placefinder
tools/tofu.sh t08-iac/infra destroy
t08-iac/destroy-state.sh      # erst am Kursende, nach allen anderen destroy-Aufrufen
```

## Fragen zum Weiterdenken

- Was steht im State, und warum gehört er nicht ins Git-Repository?
- Warum ist OIDC-Federation sicherer als ein Access Key in den GitHub-Secrets?
- Welche Teile der Konfiguration sind anbieterspezifisch, welche ließen sich als Modul für alle drei Anbieter schreiben?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| State-Backend | S3 mit Lock-Datei | Storage Account (Blob Lease) | Cloud Storage |
| Keyless CI/CD | IAM-OIDC-Anbieter + Rolle | Managed Identity + Federated Credential | Workload Identity Federation |
| Native IaC | CloudFormation, CDK | Bicep | Infrastructure Manager |
