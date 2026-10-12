# Cloud-Übungen: AWS

Skripte für den praktischen Teil des Kurses „Cloud Computing – Konzepte und Praxis für die Softwareentwicklung“ bei Amazon Web Services (AWS). Zu jedem Termin gibt es einen Ordner mit Anleitung und Skripten. Die Gegenstücke für die anderen Anbieter liegen in `cloud-labs-azure` und `cloud-labs-gcp`; Aufbau und Ordnernamen sind dort gleich.

Jeder Teilnehmer arbeitet in der ersten Kurshälfte (Termine 1–7) mit einem Anbieter und wechselt nach der Zwischenpräsentation zu einem anderen (Termine 8–12). Wer AWS erst ab Termin 8 nutzt, richtet das Konto mit `t01-grundlagen` ein und arbeitet dann mit `t08-iac` weiter.

## Voraussetzungen

- Der Dev Container dieses Repositorys (siehe unten) – er enthält alle Werkzeuge der Übungen. Ohne Dev Container: eine Linux-Shell (WSL 2) mit AWS CLI ab Version 2.32, Docker, Python 3.12, uv, curl, dig, openssl; ab Termin 8 OpenTofu ab Version 1.10. `psql` ist optional, sonst starten die Skripte es als Container.
- Ein AWS-Konto im kostenlosen Plan (Free Plan) – Einrichtung in [t01-grundlagen](t01-grundlagen/README.md)
- Ein eigener Fork von [PlaceFinder](https://github.com/mf-iu/placefinder) auf GitHub; beim Forken „Copy the master branch only“ abwählen, sonst fehlen die Tags der Ausbaustufen (`t01`, `t02` …). Die Skripte erwarten die Container-Images unter `ghcr.io/<github-user>/placefinder:<tag>`, also z. B. `:t03` für den Stand von Termin 3. Die Images müssen öffentlich sein oder vorher lokal gebaut werden.

## Arbeitsumgebung: Dev Container

Der Ordner `.devcontainer/` beschreibt einen Container mit allen Werkzeugen der Übungen: Python 3.12 mit uv, eine eigene Docker Engine im Container (Docker in Docker), kubectl, Helm, k3d, OpenTofu, psql, osm2pgsql, pmtiles, die GitHub CLI und die AWS CLI. `tools/check-tools.sh` zeigt die installierten Versionen.

**Warum:** Alle Teilnehmer arbeiten mit denselben Werkzeugen in denselben Versionen. Auf dem Notebook sind nur WSL 2, Docker Engine und VS Code nötig; alles andere steckt im Container. Ein Neubau stellt jederzeit den Ausgangszustand her.

**Starten** (im Ubuntu-Terminal von WSL):

```bash
mkdir -p ~/kurs && cd ~/kurs
git clone https://github.com/mf-iu/cloud-labs-aws.git
git clone https://github.com/<github-user>/placefinder.git   # eigener Fork
code cloud-labs-aws
```

VS Code öffnet den Ordner in WSL und meldet „Folder contains a Dev Container configuration file“: **Reopen in Container** wählen. Ohne Meldung: F1 → „Dev Containers: Reopen in Container“. Der erste Start baut das Image und dauert 10–15 Minuten, danach startet der Container in Sekunden. Unten links zeigt VS Code dann „Dev Container: Cloud-Kurs: …“; jedes Terminal in VS Code läuft jetzt im Container.

**Was erhalten bleibt:** Der Container sieht den ganzen Ordner `~/kurs` unter `/workspaces`, PlaceFinder also unter `/workspaces/placefinder`. SSH-Schlüssel (`~/.ssh`) und die AWS-Anmeldung (`~/.aws`) liegen in WSL und überstehen einen Neubau. Docker-Images und k3d-Cluster liegen in einem Volume des Containers; `docker login` (Docker Hub) ist nach einem Neubau zu wiederholen.

**Aktualisieren:** Ändert sich `.devcontainer/`, in VS Code F1 → „Dev Containers: Rebuild Container“.

### Arbeiten im Terminal des Containers

Zeigt VS Code unten links „Dev Container: Cloud-Kurs: …“, läuft jedes Terminal dieses Fensters im Container.

- **Terminal öffnen:** Strg+Ö (deutsche Tastatur; auf einer US-Tastatur Strg+Backtick) oder *Terminal* → *New Terminal*. Die Eingabeaufforderung zeigt den Benutzer `vscode` und einen Pfad unter `/workspaces`, z. B. `vscode ➜ /workspaces/cloud-labs-aws (master) $`. Nach dem ersten Bau zeigt ein Terminal die Ausgabe von `tools/check-tools.sh`; mit einer Taste schließen und ein neues öffnen.
- **Ordner:** `/workspaces/cloud-labs-aws` (Startordner jedes Terminals) und `/workspaces/placefinder`. Es sind dieselben Dateien wie in WSL unter `~/kurs`; Änderungen sind auf beiden Seiten sofort sichtbar.
- **Erste Befehle:**

  ```bash
  tools/check-tools.sh    # alle Werkzeuge vorhanden?
  cd t01-grundlagen       # Ordner der Übung von Termin 1
  aws login --remote --region eu-central-1
  ```

- **Mehrere Terminals:** mit **+** im Terminalbereich ein weiteres öffnen, mit Strg+Umschalt+5 nebeneinander teilen – praktisch für PlaceFinder: `uv run fastapi dev …` im einen, `curl` im anderen Terminal. Ein laufendes Programm beendet Strg+C, ein Terminal `exit` oder das Papierkorb-Symbol.
- **Ports:** Ports wie 8000 leitet VS Code automatisch weiter (Reiter *Ports* neben *Terminal*); `http://localhost:8000` funktioniert dann auch im Browser unter Windows.
- **Container oder WSL:** Im Container stehen alle Kurswerkzeuge zur Verfügung, aber nicht die eigene Shell-Konfiguration aus WSL. Befehle außerhalb des Containers laufen im Ubuntu-Fenster, z. B. `git clone` vor dem ersten Start und `ssh-keygen` für den SSH-Schlüssel (siehe [t01-grundlagen](t01-grundlagen/README.md#ssh-schlüssel-für-die-vms)); `wsl --shutdown` in der PowerShell. Zeigt VS Code unten links nur „WSL: Ubuntu-24.04“, ist der Ordner ohne Container geöffnet: F1 → „Dev Containers: Reopen in Container“.
- **Nach einem Neustart:** VS Code öffnet den Ordner meist wieder im Container. Sonst *File* → *Open Recent* und den Eintrag mit „[Dev Container]“ wählen. Der Container startet in Sekunden; neu gebaut wird nur, wenn sich `.devcontainer/` geändert hat.

## Einrichtung

Im Terminal des Dev Containers:

```bash
cp config.example.env config.env           # persönliche Einstellungen eintragen
aws login --remote --region eu-central-1   # Anmeldung, siehe t01-grundlagen
t01-grundlagen/check-cli.sh                # prüft CLI, Anmeldung und Region
```

`config.env` und der Ordner `.state/` gehören nur auf den eigenen Rechner und sind in `.gitignore` eingetragen. In `.state/` merken sich die Skripte die IDs der angelegten Ressourcen, damit die Aufräumskripte sie wiederfinden, außerdem Downloads und Zugangsdaten der Übungsdatenbank.

## Übersicht

| Termin | Ordner | Inhalt | Werkzeug |
|---|---|---|---|
| 1 | [t01-grundlagen](t01-grundlagen/README.md) | Konto absichern, CLI-Anmeldung, Budget-Alarm | AWS CLI |
| 2 | [t02-vm](t02-vm/README.md) | PlaceFinder v0 per cloud-init auf einer EC2-VM (IaaS) | AWS CLI |
| 3 | [t03-container](t03-container/README.md) | Image in Amazon ECR, Betrieb mit ECS Express Mode (Serverless Container) | AWS CLI, Docker |
| 4 | [t04-netzwerk](t04-netzwerk/README.md) | VPC mit öffentlichen und privaten Subnetzen, Security Groups, Diagnose | AWS CLI |
| 5 | [t05-rest-api](t05-rest-api/README.md) | Neue API-Version ausrollen und testen, API Gateway mit Rate Limit | AWS CLI |
| 6 | [t06-datenbank](t06-datenbank/README.md) | RDS for PostgreSQL mit PostGIS, Import von cities15000, räumliche Abfragen | AWS CLI, psql |
| 7 | [t07-objektspeicher](t07-objektspeicher/README.md) | S3-Bucket, Pre-Signed URLs, Range Requests, CORS, Lebenszyklusregeln | AWS CLI |
| 8 | [t08-iac](t08-iac/README.md) | Infrastruktur der Zwischenpräsentation als OpenTofu-Code, Remote State, GitHub Actions ohne Schlüssel (OIDC) | OpenTofu |
| 9 | [t09-serverless](t09-serverless/README.md) | Täglicher GeoNames-Abgleich als Lambda-Function mit EventBridge Scheduler | OpenTofu, Python |
| 10 | [t10-datenanalyse](t10-datenanalyse/README.md) | GeoParquet im Data Lake, Abfragen mit DuckDB und Athena, Overture Maps | OpenTofu, DuckDB |
| 11 | [t11-ml](t11-ml/README.md) | Modell-Endpunkt `/estimate`, MLflow-Artefakte in S3 | OpenTofu |

Termin 12 (Abschluss) hat keinen eigenen Ordner; das Abschlussprojekt baut auf `t08-iac` auf.

## Ablauf jeder Übung

1. Ressourcen anlegen: `create-….sh`, `deploy.sh` bzw. `tools/tofu.sh <ordner> apply`
2. Ausprobieren: Testbefehle aus der Anleitung des Termins
3. **Aufräumen:** `destroy-….sh` bzw. `tools/tofu.sh <ordner> destroy`
4. Kontrolle: `tools/find-leftovers.sh` listet übrig gebliebene Ressourcen auf

Die Skripte fragen vor dem Löschen nach. Mit `ASSUME_YES=1` vor dem Befehl entfällt die Rückfrage.

**Namen und Tags:** Alle Ressourcen heißen `<prefix>-<owner>-…`, z. B. `pf-mf-t02-vm`, und tragen die Tags `course=cloud-computing` und `lab=<termin>`. So bleiben die Ressourcen mehrerer Teilnehmer in einem Konto unterscheidbar.

**Ab Termin 8 mit OpenTofu:** `t08-iac/bootstrap-state.sh` legt einmalig den S3-Bucket für den Remote State an. Danach läuft jede Konfiguration über `tools/tofu.sh`, das den Backend-Zugang und die gemeinsamen Variablen aus `config.env` setzt:

```bash
tools/tofu.sh t08-iac/infra plan
tools/tofu.sh t08-iac/infra apply
tools/tofu.sh t08-iac/infra destroy
```

## Kostenregeln

- Gleich am ersten Tag den Budget-Alarm einrichten (`t01-grundlagen/create-budget.sh`).
- Nach jeder Übung alles abbauen. Teuer im Dauerbetrieb sind vor allem NAT-Gateways, Load Balancer (auch der von ECS Express Mode), RDS-Instanzen und öffentliche IPv4-Adressen.
- Nicht auf den kostenpflichtigen Plan umstellen. Im Free Plan zahlt AWS aus dem Guthaben; ist es aufgebraucht oder sind sechs Monate um, wird das Konto geschlossen, aber nichts berechnet.
- Preisangaben in den Anleitungen sind Richtwerte für die Region Frankfurt (Stand Oktober 2026) und dienen nur der Orientierung.

## Daten und Lizenzen

- GeoNames (`cities15000`, tägliche Änderungsdateien): CC BY 4.0, Namensnennung „GeoNames“
- OpenStreetMap und Overture Maps: ODbL bzw. CDLA Permissive 2.0, je nach Thema
- Geodaten werden nie eingecheckt, sondern von den Skripten geladen.

## Konventionen

Anleitungen auf Deutsch, Skripte, Kommentare und Commit-Messages auf Englisch. Die Shell-Skripte sind mit ShellCheck geprüft (`shellcheck */*.sh`), die OpenTofu-Dateien mit `tofu fmt`.
