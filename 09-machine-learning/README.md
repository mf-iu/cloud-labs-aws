# 09 – Machine Learning: MLflow mit Artefakten in S3

**Ziel:** Dieselben Läufe wie in der lokalen Übung, aber die Modelle landen im S3-Bucket von `base`. Der Tracking-Server läuft weiter auf dem eigenen Rechner; nur sein Artefakt-Speicher wechselt. `train.py` und `estimate.py` aus `cloud-labs-local` laufen unverändert.

**Baut auf:** [06-infrastructure-as-code](../06-infrastructure-as-code/README.md) (`base` mit dem Bucket); lokal [cloud-labs-local/11-machine-learning](https://github.com/mf-iu/cloud-labs-local/tree/master/11-machine-learning) · **Termin:** 11 (Zusatz)

**Kosten:** praktisch keine. Ein Modell hat 1 bis 12 MB; Speicher, Anfragen und der Datentransfer zum eigenen Rechner bleiben im Freikontingent. Es entsteht keine neue Ressource.

| Datei | Aufgabe |
|---|---|
| `start-mlflow.sh` | `start-mlflow.sh` aus `cloud-labs-local` starten, mit den Artefakten unter `s3://<bucket von base>/mlflow/` und eigener Datenbank in `.state/mlflow` |

## Voraussetzungen

- `base` steht: `tools/tofu.sh 06-infrastructure-as-code/base output bucket` zeigt den Bucket.
- Die Schritte 1 bis 5 aus `cloud-labs-local/11-machine-learning` sind bekannt (Server starten, trainieren, vergleichen, freigeben).
- `aws login` ist aktiv; `01-account/check-cli.sh` prüft das.
- Der lokale Server ist beendet; beide nutzen Port 5000.

## Zusatz im Termin

```bash
cd /workspaces/cloud-labs-aws
09-machine-learning/start-mlflow.sh            # Terminal 1: Server, Artefakte in S3
```

In einem zweiten Terminal dieselben Skripte wie lokal:

```bash
cd /workspaces/cloud-labs-local/11-machine-learning
uv run train.py                                # drei Läufe, Random Forest als Version 1
uv run estimate.py --release 1
```

Die Modelle im Bucket ansehen:

```bash
cd /workspaces/cloud-labs-aws
bucket=$(tools/tofu.sh 06-infrastructure-as-code/base output -raw bucket)
aws s3 ls "s3://$bucket/mlflow/" --recursive --human-readable --summarize
```

`start-mlflow.sh` liest den Bucket aus den Ausgaben von `base` (`base_output bucket` in `lib/provider.sh`) und ruft `cloud-labs-local/11-machine-learning/start-mlflow.sh` mit drei Umgebungsvariablen auf:

| Variable | Wert | Warum |
|---|---|---|
| `MLFLOW_ARTIFACTS_DESTINATION` | `s3://<bucket>/mlflow` | Modelle und Eingabebeispiele in den Bucket |
| `MLFLOW_BACKEND_STORE_URI` | SQLite in `.state/mlflow` dieses Repositorys | Jedes Experiment merkt sich den Ort seiner Artefakte; die lokalen Läufe zeigen auf Dateien, diese auf den Bucket. Getrennte Datenbanken halten beides auseinander. |
| `MLFLOW_EXTRA_PACKAGES` | `boto3[crt]` | Der Server schreibt mit boto3 in S3. |

**Wer braucht Zugangsdaten?** Nur der Server. `train.py` lädt das Modell über den Server hoch (*proxied artifacts*), `estimate.py` lädt es über ihn herunter. boto3 liest die Anmeldung von `aws login` aus dem Profil in `AWS_PROFILE` (aus `config.env`) und erneuert sie selbst, solange die Anmeldung gilt. Dafür braucht es das Extra `crt` (AWS Common Runtime); ohne es laufen die Schlüssel nach etwa 15 Minuten ab.

Die Dateien einer Version liegen unter `mlflow/<experiment>/models/m-<id>/artifacts/`: `model.skops` ist das Modell, `MLmodel` beschreibt es, dazu `requirements.txt` und `input_example.json`. Die Läufe, Metriken und die Registry stehen dagegen nur in der Datenbank auf dem eigenen Rechner. Im Team liefe der Server deshalb selbst in der Cloud, mit einer Datenbank wie RDS for PostgreSQL. Das bietet SageMaker AI als verwaltetes MLflow an (im Kurs nur vorgestellt).

Die Modelle bleiben bis zum Kursende im Bucket von `base`. Das Abschlussprojekt (Thema 4: Endpunkt `/estimate`) kann das freigegebene Modell von dort laden.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No output bucket from base` | `base` fehlt oder ist abgebaut. | `tools/tofu.sh 06-infrastructure-as-code/base apply` |
| `An MLflow server already answers on port 5000` | Der lokale Server läuft noch. | ihn mit Ctrl+C beenden |
| `ExpiredToken` oder `Unable to locate credentials` im Log des Servers | Die Anmeldung ist abgelaufen. | `aws login --remote`, Server neu starten |
| `AccessDenied` beim Hochladen | Das Profil gehört zu einem anderen Konto als `base`. | `AWS_PROFILE` in `config.env` prüfen |
| `train.py` hängt beim Hochladen | Der Server erreicht S3 nicht. | Log des Servers in Terminal 1 lesen |

## Aufräumen

Den Server mit Ctrl+C beenden. Die Modelle können für das Abschlussprojekt bleiben. Wer sie löschen will, löscht Bucket-Inhalt und Datenbank zusammen; sonst zeigt die Registry auf fehlende Dateien:

```bash
bucket=$(tools/tofu.sh 06-infrastructure-as-code/base output -raw bucket)
aws s3 rm "s3://$bucket/mlflow/" --recursive
rm -r .state/mlflow
tools/find-leftovers.sh                        # nur noch base
```

## Fragen zum Weiterdenken

- Der Server hält die Zugangsdaten, die Skripte nicht. Was bedeutet das für ein Team, und was für einen Server, der im Internet erreichbar ist?
- Warum gehört die Datenbank mit Läufen und Registry ebenso in die Cloud wie die Artefakte, sobald mehrere Personen trainieren?
- Ein Modell im Bucket ist eine Datei mit Code, der beim Laden läuft. Wer darf in `mlflow/` schreiben, und was schützt skops?
- Was kostet verwaltetes MLflow in SageMaker AI im Vergleich zu einem eigenen Server auf ECS?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Artefakte | S3, `s3://` | Blob Storage, `wasbs://` | Cloud Storage, `gs://` |
| Der Server liest mit | Anmeldung von `aws login` (boto3) | Verbindungszeichenkette des Speicherkontos | Application Default Credentials |
| Verwaltetes Tracking | SageMaker AI mit MLflow | Azure Machine Learning (MLflow-kompatibel) | Model Registry der Plattform |
