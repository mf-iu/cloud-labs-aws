# 04 – Netze: VPC bei AWS

Die Übung von Termin 4 läuft im Termin: Nach dem Entwurf auf Papier wird das Netz als VPC bei AWS angelegt, mit dem Entwurf verglichen und wieder gelöscht (ca. 45 Minuten). Alles Weitere ist **Zusatz** – freiwillig und ohne Folgen für spätere Termine: Test-VMs und NAT-Gateway. Diagnose einer HTTPS-Anfrage und die Demo mit Gateway API und cert-manager im lokalen Cluster stehen in [cloud-labs-local/04-cluster-network](https://github.com/mf-iu/cloud-labs-local/tree/master/04-cluster-network).

| Skript | Aufgabe |
|---|---|
| `create-vpc.sh` | VPC mit Subnetzen, Routing-Tabellen und Security Groups anlegen; optional Test-VMs und NAT-Gateway |
| `check-vpc.sh` | Netz mit dem Entwurf vergleichen; mit Test-VMs auch: Was ist von wo erreichbar? |
| `destroy-vpc.sh` | alles wieder löschen |

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

## Zusatz: Test-VMs und NAT-Gateway

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

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Netz | VPC, regional | Virtual Network, regional | VPC, global |
| Subnetz | eine Zone | alle Zonen der Region | regional |
| Reservierte Adressen je Subnetz | 5 | 5 | 4 |
| Firewall | Security Groups, Network ACLs | Network Security Groups | Firewall-Regeln mit Netzwerk-Tags |
| Ausgehend ohne öffentliche Adresse | NAT-Gateway | NAT-Gateway | Cloud NAT |
| Zugang ohne Bastion-Host | Session Manager | Azure Bastion | Identity-Aware Proxy (IAP) |
