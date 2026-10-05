# T11 – Modell als Service

**Ziel:** Das Modell zur Einwohnerschätzung aus Termin 11 wird als Endpunkt `/estimate` von PlaceFinder bereitgestellt. MLflow speichert Experimente lokal und Artefakte in S3; das freigegebene Modell liegt unter `models/` im selben Bucket. Der Dienst darf über seine Task Role nur dieses Präfix lesen.

**Kosten:** Dienst mit 0,5 vCPU und 1 GB plus Load Balancer ca. 1,2 USD pro Tag. Managed-ML-Plattformen (SageMaker AI) werden nur vorgestellt, weil schon kleine Endpunkte deutlich mehr kosten.

## Schritte

```bash
cd ..
tools/tofu.sh t11-ml/infra apply           # Bucket, Rollen, Dienst mit Image :t11
tools/tofu.sh t11-ml/infra output
```

MLflow lokal mit Artefakten in S3 (Zugangsdaten aus `aws login`):

```bash
eval "$(aws configure export-credentials --format env)"
bucket=$(tools/tofu.sh t11-ml/infra output -raw bucket)
uvx --with boto3 mlflow server --backend-store-uri sqlite:///.state/mlflow.db \
  --artifacts-destination "s3://$bucket/mlflow" --port 5000
```

Training im Notebook von Termin 11 mit `mlflow.set_tracking_uri("http://localhost:5000")`. Das beste Modell exportieren und hochladen:

```bash
t11-ml/upload-model.sh model.joblib       # startet die Tasks neu, damit sie das Modell laden
curl "$(tools/tofu.sh t11-ml/infra output -raw service_url)/estimate?lat=50.98&lon=11.03"
```

PlaceFinder liest beim Start `MODEL_URI` (z. B. `s3://…/models/estimate/model.joblib`) mit den Rechten der Task Role.

## Aufräumen

```bash
tools/tofu.sh t11-ml/infra destroy
```

## Fragen zum Weiterdenken

- Welche Informationen braucht man, um ein Modell später nachvollziehen zu können (Daten, Code, Parameter, Metriken)?
- Wie würde man ein neues Modell schrittweise ausrollen und mit dem alten vergleichen?
- Was kostet ein SageMaker-AI-Endpunkt im Vergleich, und wann lohnt er sich?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| ML-Plattform | SageMaker AI | Azure Machine Learning | Vertex AI |
| Modell-Endpunkt hier | ECS Express Mode | Container Apps | Cloud Run |
| Rechte des Dienstes | Task Role | Managed Identity | Service Account |
