# T02 – PlaceFinder auf einer VM (IaaS)

**Ziel:** PlaceFinder v0 läuft auf einer EC2-VM. Die VM richtet sich beim ersten Start selbst ein (cloud-init): Pakete installieren, Code klonen, Abhängigkeiten mit uv installieren, GeoNames-Daten laden, Dienst starten. So wird sichtbar, was bei IaaS alles in der eigenen Verantwortung liegt.

**Kosten:** `t3.micro` mit 10 GB Speicher und öffentlicher IPv4-Adresse, ca. 0,02 USD pro Stunde aus dem Guthaben. Nach der Übung löschen.

## Voraussetzungen

- `t01-grundlagen` erledigt, `aws login` aktiv
- SSH-Schlüssel `~/.ssh/id_ed25519`, einmalig im **Ubuntu-Terminal von WSL** angelegt, nicht im Container (siehe [t01-grundlagen](../t01-grundlagen/README.md#ssh-schlüssel-für-die-vms))
- PlaceFinder-Fork mit dem Tag `t01` unter `PLACEFINDER_REPO` (öffentlich lesbar)

## Schritte

```bash
./create-vm.sh          # oder: ./create-vm.sh <tag/branch>, Standard t01
```

Das Skript

1. legt eine Security Group an, die SSH (22) und die API (8000) nur von der eigenen IP-Adresse zulässt,
2. importiert den SSH-Schlüssel als Key Pair,
3. startet eine VM mit dem aktuellen Ubuntu-24.04-Image von Canonical und `cloud-init.yaml` als User Data,
4. wartet, bis die API antwortet (erster Start ca. 3–5 Minuten).

## Prüfen

```bash
ssh ubuntu@<ip> cloud-init status --wait     # Einrichtung abgeschlossen?
ssh ubuntu@<ip> journalctl -u placefinder -n 50
curl "http://<ip>:8000/places?q=Erfurt"
```

Die IP-Adresse steht in der Ausgabe von `create-vm.sh` und in `../.state/t02.env`.

## Aufräumen

```bash
./destroy-vm.sh
```

## Fragen zum Weiterdenken

- Was müsste man hier selbst erledigen, was eine PaaS übernimmt (Updates, TLS, Neustart, Skalierung, Logs)?
- Warum verlangt das Skript `HttpTokens=required` für den Metadatendienst (IMDSv2)?
- Was passiert mit der Anwendung, wenn die VM neu startet? Und wenn sie beendet und neu angelegt wird?
- Wie würde man die API über HTTPS anbieten?

## Container und Compose

Die Container-Übungen von Termin 2 hängen nicht vom Anbieter ab. Sie stehen in der README von PlaceFinder, Abschnitt *Container* (Musterlösung ab Tag `t02`):

- Dockerfile und `.dockerignore` schreiben, Image bauen, starten, Schichten ansehen (Übung im Termin)
- `compose.yaml` mit PlaceFinder und einem kleinen Übungsdienst (Selbstlernphase); eine Datenbank folgt in Termin 6
- optional: Image verkleinern und mit Trivy scannen; Image in die GitHub Container Registry laden (für Termin 3 nötig)

Alle Container-Befehle laufen im **Dev Container** (`cd /workspaces/placefinder`). Er hat eine eigene Docker Engine. Ob eine Anmeldung bei Docker Hub nötig ist und was bei `toomanyrequests` hilft, steht im README von PlaceFinder unter [Docker Hub: anmelden oder nicht?](https://github.com/mf-iu/placefinder#docker-hub-anmelden-oder-nicht).

Die Musterlösung holt man so in den eigenen Fork:

```bash
cd /workspaces/placefinder
git remote add upstream https://github.com/mf-iu/placefinder.git   # einmalig
git fetch upstream --tags
git diff t02 -- Dockerfile compose.yaml      # eigene Lösung mit der Musterlösung vergleichen
```

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| VM | EC2 `t3.micro` | Virtual Machines `Standard_B1s` | Compute Engine `e2-micro` |
| Firewall | Security Group | Network Security Group | VPC-Firewall-Regel |
| Startskript | User Data (cloud-init) | Custom Data (cloud-init) | Metadaten `user-data` (cloud-init) |
