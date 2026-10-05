# T03 – Registry und Serverless Container

**Ziel:** Das PlaceFinder-Image liegt in Amazon ECR und läuft mit **Amazon ECS Express Mode** auf Fargate. Express Mode legt mit einem Aufruf Task Definition, Dienst, Application Load Balancer mit HTTPS-Zertifikat, Autoscaling und Logs an.

**Kosten:** Fargate-Task mit 0,25 vCPU und 512 MB ca. 0,01 USD pro Stunde, Load Balancer ca. 0,03 USD pro Stunde plus öffentliche IPv4-Adressen – zusammen etwa 1 USD pro Tag aus dem Guthaben. ECR: 500 MB im Free Tier. **Nach der Übung löschen.**

AWS App Runner nimmt seit 30. April 2026 keine neuen Kunden mehr an; AWS empfiehlt stattdessen ECS Express Mode.

## Voraussetzungen

- Docker im Dev Container
- Image `$PLACEFINDER_IMAGE:t03` (öffentlich auf ghcr.io oder lokal gebaut: `docker build -t ghcr.io/<user>/placefinder:t03 .`)
- Das Konto hat eine Default-VPC (Standard bei neuen Konten). Express Mode legt Load Balancer und Tasks dort an.

## Schritte

```bash
./push-image.sh                 # ECR-Repository anlegen, Image hochladen
./deploy.sh                     # Express-Mode-Dienst anlegen, auf /health warten
```

`push-image.sh` legt das Repository mit Schwachstellen-Scan beim Push und einer Lebenszyklusregel an, die nur die fünf neuesten Images behält. `deploy.sh` legt zwei IAM-Rollen an: die Execution Role, mit der ECS das Image lädt und Logs schreibt, und die Infrastructure Role, mit der Express Mode Load Balancer und Autoscaling verwaltet.

Der erste Start dauert etwa fünf Minuten. Der Status lässt sich verfolgen mit:

```bash
aws ecs describe-express-gateway-service --service-arn <arn> --query service.status
```

## Prüfen

```bash
url=$(grep SERVICE_URL ../.state/t03.env | cut -d= -f2)
curl "$url/health"
curl "$url/places?q=Berlin"
aws ecr describe-image-scan-findings --repository-name pf-<owner>-placefinder --image-id imageTag=t03
```

In der ECS-Konsole unter *Clusters* → *default* sind Dienst, Tasks, Load Balancer und Logs zu sehen.

## Aufräumen

```bash
./destroy.sh     # Dienst (inkl. Load Balancer), Log-Gruppe, ECR-Repository, Rollen
```

Wer in Termin 5 weiterarbeiten will, kann den Dienst bis dahin stehen lassen – das kostet dann aber etwa 1 USD pro Tag.

## Fragen zum Weiterdenken

- Warum skaliert ECS Express Mode nicht auf null, Cloud Run und Azure Container Apps dagegen schon? Was bedeutet das für die Kosten?
- Welche Ressourcen hat Express Mode im Hintergrund angelegt (*EC2* → *Load Balancers*, *Target Groups*, *Security Groups*)?
- Wofür ist die Infrastructure Role nötig, und warum muss sie beim Löschen als Letztes entfernt werden?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Registry | Amazon ECR | Azure Container Registry (hier: ghcr.io) | Artifact Registry |
| Serverless Container | ECS Express Mode auf Fargate | Azure Container Apps | Cloud Run |
| Skalierung auf null | nein | ja | ja |
