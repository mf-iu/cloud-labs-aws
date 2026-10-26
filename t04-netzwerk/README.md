# T04 – Netze: VPC bei AWS, Diagnose, Gateway API lokal

Die Übung von Termin 4 läuft im Termin: Nach dem Entwurf auf Papier wird das Netz als VPC bei AWS angelegt, mit dem Entwurf verglichen und wieder gelöscht (ca. 45 Minuten). Alles Weitere ist **Zusatz** – freiwillig und ohne Folgen für spätere Termine: Test-VMs und NAT-Gateway, Diagnose einer HTTPS-Anfrage und die Demo mit Gateway API und cert-manager im lokalen k3d-Cluster.

| Skript | Aufgabe |
|---|---|
| `create-vpc.sh` | VPC mit Subnetzen, Routing-Tabellen und Security Groups anlegen; optional Test-VMs und NAT-Gateway |
| `check-vpc.sh` | Netz mit dem Entwurf vergleichen; mit Test-VMs auch: Was ist von wo erreichbar? |
| `destroy-vpc.sh` | alles wieder löschen |
| `diagnose.sh` | DNS, TCP, TLS und Zertifikat eines Hosts anzeigen |
| `gateway-up.sh`, `gateway-down.sh` | lokaler Cluster mit Gateway API, cert-manager und PlaceFinder über HTTPS (Dateien in `k8s/`) |

## Im Termin: Netz anlegen, prüfen, löschen

**Ziel:** eine VPC `10.20.0.0/16` mit je zwei öffentlichen, Anwendungs- und Datenbank-Subnetzen in zwei Availability Zones, passenden Routing-Tabellen und Security Groups, die aufeinander verweisen.

**Kosten:** VPC, Subnetze, Routing-Tabellen und Security Groups sind kostenlos; ohne die Optionen `--with-vm` und `--with-nat` entsteht nichts, was Geld kostet.

### Aufbau

| Subnetz | CIDR | Zone | Route `0.0.0.0/0` |
|---|---|---|---|
| public-a / public-b | 10.20.0.0/24, 10.20.1.0/24 | a / b | Internet-Gateway |
| app-a / app-b | 10.20.10.0/24, 10.20.11.0/24 | a / b | keine (mit `--with-nat`: NAT-Gateway) |
| db-a / db-b | 10.20.20.0/24, 10.20.21.0/24 | a / b | keine |

| Security Group | Eingehend erlaubt |
|---|---|
| sg-lb | 443 von überall |
| sg-app | 8000 nur von sg-lb |
| sg-db | 5432 nur von sg-app |
| sg-ssh (mit `--with-vm`) | 22 nur von der eigenen IP-Adresse – für den Bastion-Host |
| sg-ssh-from-bastion (mit `--with-vm`) | 22 nur von sg-ssh – für die private VM |

### Anlegen

```bash
./create-vpc.sh
```

Das Skript läuft ein bis zwei Minuten und zeigt am Ende eine Übersicht der Subnetze.

### Prüfen

```bash
./check-vpc.sh
```

Das Skript vergleicht das angelegte Netz mit dem Entwurf und markiert Abweichungen mit `UNEXPECTED`:

| Prüfung | Erwartung |
|---|---|
| Adressbereich je Subnetz | wie im Entwurf, z. B. `app-a` = `10.20.10.0/24` |
| Route `0.0.0.0/0` je Subnetz | `public-*`: Internet-Gateway, `app-*` und `db-*`: keine (mit `--with-nat`: `app-*` zum NAT-Gateway) |
| eingehende Regeln je Security Group | `sg-lb`: 443 von `0.0.0.0/0`, `sg-app`: 8000 von `sg-lb`, `sg-db`: 5432 von `sg-app` |

Danach zeigt es alle Subnetze mit der Zahl der freien Adressen – AWS reserviert in jedem Subnetz fünf Adressen, ein `/24` hat also 251 nutzbare.

Zum Ausprobieren: in der Konsole des Anbieters eine Regel ändern, etwa die Datenbank aus dem ganzen Internet erlauben, und `./check-vpc.sh` erneut aufrufen. Danach die Änderung zurücknehmen.

Von Hand:

```bash
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<vpc-id> --output table
aws ec2 describe-security-groups --filters Name=vpc-id,Values=<vpc-id> \
  --query 'SecurityGroups[].[GroupName,IpPermissions[0].FromPort,IpPermissions[0].UserIdGroupPairs[0].GroupId]' --output table
```

### Aufräumen – gehört zur Übung

```bash
./destroy-vpc.sh
../tools/find-leftovers.sh
```

`destroy-vpc.sh` löscht in umgekehrter Reihenfolge: VMs, NAT-Gateway, Elastic IP, Security Groups, Routing-Tabellen, Subnetze, Internet-Gateway, VPC. Erst wenn beide Befehle durchgelaufen sind, ist die Übung fertig.

### Fragen zum Weiterdenken

- Was macht ein Subnetz bei AWS „öffentlich“? Was fehlt der privaten VM in `app-a`, um Updates aus dem Internet zu laden?
- Warum verweisen die Security Groups aufeinander statt auf Adressbereiche?
- Wozu sind die Datenbank-Subnetze in zwei Zonen nötig, auch wenn die Datenbank nur in einer läuft?
- Was kostet das NAT-Gateway im Monat, wenn man es vergisst? Welche günstigeren Wege gibt es zu S3 (Gateway-Endpunkt)?

## Zusatz 1: Test-VMs und NAT-Gateway

**Kosten:** Die beiden Test-VMs (`t3.micro`) kosten zusammen ca. 0,03 USD pro Stunde einschließlich der öffentlichen IPv4-Adresse, das **NAT-Gateway ca. 0,05 USD pro Stunde plus Datenmenge**. Am selben Tag wieder löschen.

Die Optionen gelten nur beim Anlegen; ein bestehendes Netz erst mit `./destroy-vpc.sh` löschen.

```bash
./create-vpc.sh --with-vm            # zusätzlich zwei Test-VMs
./create-vpc.sh --with-vm --with-nat # zusätzlich NAT-Gateway (kostet!)
./check-vpc.sh
```

Mit `--with-vm` entstehen zwei VMs: ein **Bastion-Host** in `public-a` mit öffentlicher Adresse und eine **private VM** in `app-a` ohne öffentliche Adresse. Die private VM ist nur über den Bastion-Host erreichbar (SSH-Sprung mit `-J`).

Ein Bastion-Host ist das klassische Muster für den Zugang zu privaten Subnetzen. In Produktion ersetzt man ihn besser durch den AWS Systems Manager Session Manager: kein offener Port 22, Anmeldung über IAM, jede Sitzung protokolliert.

Mit Test-VMs meldet sich `check-vpc.sh` zusätzlich am Bastion-Host an, springt von dort auf die private VM und prüft vier Erwartungen an die Erreichbarkeit:

| Prüfung | ohne `--with-nat` | mit `--with-nat` |
|---|---|---|
| Bastion-Host erreicht das Internet | ja | ja |
| private VM über den Bastion-Host erreichbar | ja | ja |
| private VM erreicht das Internet | nein | ja (über das NAT-Gateway) |
| private VM direkt von hier erreichbar | nein | nein |

Die private VM löst Namen auch ohne NAT-Gateway auf – der DNS-Resolver der VPC ist Teil des Netzes. Die Verbindung zur Website scheitert dann erst danach.

Von Hand:

```bash
ssh ubuntu@<bastion-ip>
ssh -J ubuntu@<bastion-ip> ubuntu@<private-ip>
```

Die Adressen stehen in der Ausgabe von `create-vpc.sh` und in `../.state/t04.env`. Wechselt die eigene IP-Adresse (anderes WLAN), lässt sg-ssh keine Verbindung mehr zu – dann `./destroy-vpc.sh` und neu anlegen.

Danach aufräumen wie oben: `./destroy-vpc.sh`.

## Zusatz 2: Diagnose

```bash
./diagnose.sh                          # www.openstreetmap.org
./diagnose.sh https://<eigene-url>     # z. B. der Dienst aus Termin 3
```

Das Skript zeigt nacheinander die DNS-Antwort mit TTL und Resolver, die Delegation ab der Root-Zone (`dig +trace`), Verbindungsaufbau und TLS-Handshake (`curl --verbose`), die Zeit bis zu jedem Schritt (`curl --write-out`) und die Zertifikatskette (`openssl s_client`). Blockiert das Netz DNS-Anfragen an andere Server als den eigenen Resolver (manche Firmen- und Hochschulnetze), bleibt der Abschnitt `dig +trace` leer.

## Zusatz 3: Gateway API und TLS lokal

**Kosten:** keine – alles läuft im Dev Container. Der Cluster `net` hat einen Node und braucht mit allen Pods rund 1,5 GB Arbeitsspeicher; läuft der Cluster `pf` aus Termin 3 noch, ihn bei Bedarf mit `k3d cluster stop pf` anhalten.

```bash
./gateway-up.sh      # beim ersten Mal 3–5 Minuten
curl --cacert ../.state/course-ca.crt --resolve placefinder.test:8443:127.0.0.1 \
  "https://placefinder.test:8443/places?q=Erfurt"
./gateway-down.sh
```

`gateway-up.sh` baut die Demo aus Termin 4 nach und ist mehrfach aufrufbar:

1. Cluster `net` mit k3d; Port 8443 des Dev Containers führt auf Port 443 des Clusters.
2. `k8s/traefik-gw.yaml` schaltet den Gateway-API-Provider des Traefik ein, den k3s mitbringt; Traefik legt die GatewayClass `traefik` an.
3. PlaceFinder mit dem Manifest aus Termin 3 (`deploy/k8s/` im Repository `placefinder`); fehlt das Image, baut es `../t03-container/build-image.sh`.
4. cert-manager mit Helm, Gateway-API-Unterstützung über `k8s/cert-manager-values.yaml`.
5. Eine eigene Kurs-CA in `../.state/course-ca.crt` (30 Tage gültig, wird danach neu angelegt) als Secret für den ClusterIssuer `k8s/issuer.yaml`.
6. Gateway (`k8s/gateway.yaml`) und HTTPRoute (`k8s/route.yaml`); cert-manager legt das Zertifikat `pf-tls` von selbst an.
7. Eine Anfrage über HTTPS, geprüft gegen die Kurs-CA.

`--resolve` ersetzt den DNS-Eintrag für `placefinder.test` (die Endung `.test` ist für Tests reserviert), `--cacert` vertraut der Kurs-CA. Ohne `--cacert` bricht `curl` mit einem Zertifikatsfehler ab; `curl --verbose` zeigt Handshake, Zertifikat und Aussteller.

```bash
kubectl get gatewayclass,gateway,httproute
kubectl describe certificate pf-tls       # ausgestellt von course-ca, Laufzeit, Erneuerung
openssl x509 -in ../.state/course-ca.crt -noout -subject -enddate
```

**NetworkPolicies:**

```bash
kubectl apply --filename k8s/networkpolicies.yaml
curl --cacert ../.state/course-ca.crt --resolve placefinder.test:8443:127.0.0.1 \
  "https://placefinder.test:8443/places?q=Erfurt"          # geht weiter: über das Gateway
kubectl run test --rm --stdin --tty --image=busybox:1.37 -- \
  wget --timeout 3 --quiet --output-document - http://placefinder   # blockiert
kubectl delete --filename k8s/networkpolicies.yaml
```

`default-deny` verbietet allen Pods im Namespace `default` eingehenden Verkehr, `placefinder-from-gateway` erlaubt PlaceFinder Port 8000 aus dem Namespace `kube-system`, in dem Traefik läuft. k3s setzt NetworkPolicies mit einem eingebauten Controller durch.

**Typische Probleme**

- Keine GatewayClass `traefik` nach vier Minuten: `kubectl --namespace kube-system get pods` – läuft Traefik nach dem Neustart wieder?
- Zertifikat nicht `Ready`: `kubectl describe certificate pf-tls` und `kubectl --namespace cert-manager logs deployment/cert-manager`.
- `curl` erreicht nichts: Läuft der Befehl im Terminal des Dev Containers? Port 8443 gibt es nur dort.

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Netz | VPC, regional | Virtual Network, regional | VPC, global |
| Subnetz | eine Zone | alle Zonen der Region | regional |
| Reservierte Adressen je Subnetz | 5 | 5 | 4 |
| Firewall | Security Groups, Network ACLs | Network Security Groups | Firewall-Regeln mit Netzwerk-Tags |
| Ausgehend ohne öffentliche Adresse | NAT-Gateway | NAT-Gateway | Cloud NAT |
| Zugang ohne Bastion-Host | Session Manager | Azure Bastion | Identity-Aware Proxy (IAP) |
