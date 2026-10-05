# T04 – VPC mit öffentlichen und privaten Subnetzen

**Ziel:** Der Netzentwurf aus der Übung von Termin 4 wird als echtes Netz bei AWS angelegt: eine VPC `10.20.0.0/16` mit je zwei öffentlichen, Anwendungs- und Datenbank-Subnetzen in zwei Availability Zones, passenden Routing-Tabellen und Security Groups, die aufeinander verweisen.

**Kosten:** VPC, Subnetze, Routing-Tabellen und Security Groups sind kostenlos. Die optionale Test-VM kostet ca. 0,02 USD pro Stunde, das optionale **NAT-Gateway ca. 0,05 USD pro Stunde plus Datenmenge** – am selben Tag wieder löschen.

## Aufbau

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
| sg-ssh (nur mit `--with-vm`) | 22 nur von der eigenen IP-Adresse |

## Schritte

```bash
./create-vpc.sh                      # nur das Netz
./create-vpc.sh --with-vm            # zusätzlich Test-VM im öffentlichen Subnetz
./create-vpc.sh --with-vm --with-nat # zusätzlich NAT-Gateway (kostet!)
```

Am Ende zeigt das Skript alle Subnetze mit der Zahl der freien Adressen – AWS reserviert in jedem Subnetz fünf Adressen, ein `/24` hat also 251 nutzbare.

## Prüfen

```bash
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<vpc-id> --output table
aws ec2 describe-security-groups --filters Name=vpc-id,Values=<vpc-id> \
  --query 'SecurityGroups[].[GroupName,IpPermissions[0].FromPort,IpPermissions[0].UserIdGroupPairs[0].GroupId]' --output table
ssh ubuntu@<ip-der-test-vm>          # mit --with-vm
```

Netzwerkdiagnose von außen, z. B. gegen die eigene API aus Termin 3 oder einen bekannten Dienst:

```bash
./diagnose.sh www.openstreetmap.org
```

Das Skript zeigt nacheinander DNS-Antworten, die Delegation ab der Root-Zone (`dig +trace`), Verbindungsaufbau und TLS-Handshake (`curl -v`) und die Zertifikatskette (`openssl s_client`).

## Aufräumen

```bash
./destroy-vpc.sh
```

Das Skript löscht in umgekehrter Reihenfolge: VM, NAT-Gateway, Elastic IP, Security Groups, Routing-Tabellen, Subnetze, Internet-Gateway, VPC.

## Fragen zum Weiterdenken

- Was macht ein Subnetz bei AWS „öffentlich“? Was fehlt der Test-VM im Subnetz `app-a`, um Updates aus dem Internet zu laden?
- Warum verweisen die Security Groups aufeinander statt auf Adressbereiche?
- Wozu sind die Datenbank-Subnetze in zwei Zonen nötig, auch wenn die Datenbank nur in einer läuft?
- Was kostet das NAT-Gateway im Monat, wenn man es vergisst? Welche günstigeren Wege gibt es zu S3 (Gateway-Endpunkt)?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Netz | VPC, regional | Virtual Network, regional | VPC, global |
| Subnetz | eine Zone | alle Zonen der Region | regional |
| Reservierte Adressen je Subnetz | 5 | 5 | 4 |
| Firewall | Security Groups, Network ACLs | Network Security Groups | Firewall-Regeln mit Netzwerk-Tags |
