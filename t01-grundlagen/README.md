# T01 – Konto absichern, CLI und Budget-Alarm

**Ziel:** Ein AWS-Konto im Free Plan, das nicht mit dem Root-Benutzer verwendet wird, eine funktionierende AWS CLI im Dev Container und ein Budget-Alarm, der vor unerwarteten Kosten warnt.

**Kosten:** keine. Budgets mit E-Mail-Benachrichtigung sind kostenlos.

## 1. Konto anlegen (Browser)

1. Auf <https://aws.amazon.com/free> ein Konto anlegen und den **Free Plan** wählen. Die Kreditkarte dient nur der Identitätsprüfung; im Free Plan wird nichts berechnet, solange nicht auf den kostenpflichtigen Plan umgestellt wird.
2. Als Root-Benutzer anmelden und sofort **MFA** einrichten: Kontoname oben rechts → *Security credentials* → *Assign MFA device* (Authenticator-App oder Passkey).
3. Einen IAM-Benutzer für die tägliche Arbeit anlegen: *IAM* → *Users* → *Create user*, Name z. B. `admin`, *Provide user access to the AWS Management Console* aktivieren.
4. Dem Benutzer die Richtlinien `AdministratorAccess` und `SignInLocalDevelopmentAccess` zuweisen. Die zweite enthält die Rechte für die Anmeldung der CLI mit `aws login`. `AdministratorAccess` schließt sie zwar ein, aber so bleibt die Anmeldung möglich, falls die Rechte später eingeschränkt werden.
5. Abmelden, mit dem neuen IAM-Benutzer anmelden und auch für ihn MFA einrichten. Den Root-Benutzer nur noch für Kontoeinstellungen verwenden.
6. Region oben rechts auf **Europe (Frankfurt) eu-central-1** stellen.

## 2. CLI anmelden (Dev Container)

Im Terminal des Dev Containers (siehe [README](../README.md#arbeitsumgebung-dev-container)):

```bash
cp ../config.example.env ../config.env   # OWNER, ALERT_EMAIL usw. eintragen
aws --version                            # mindestens 2.32
aws login --remote --region eu-central-1
```

`aws login --remote` gibt eine URL aus. Die URL im Browser öffnen, mit dem IAM-Benutzer anmelden und den angezeigten Code in das Terminal kopieren. Die CLI erhält damit kurzlebige Zugangsdaten, die sie bis zu zwölf Stunden selbst erneuert; es gibt keine dauerhaften Access Keys, die verloren gehen könnten. Danach:

```bash
./check-cli.sh
```

Das Skript zeigt Konto, Benutzer und Region und warnt, wenn die Anmeldung mit dem Root-Benutzer erfolgt ist.

## 3. Budget-Alarm

```bash
./create-budget.sh      # Monatsbudget BUDGET_AMOUNT aus config.env, Standard 10 USD
```

AWS schickt eine E-Mail an `ALERT_EMAIL`, sobald die tatsächlichen Kosten 50 % und 80 % des Budgets überschreiten oder die Prognose für den Monat 100 % erreicht. Das Budget rechnet ohne Gutschriften: Im Free Plan bezahlt das Guthaben alles, ein Budget nach Abzug der Gutschriften bliebe immer bei 0 USD und würde nie warnen. Im Free Plan kommen zusätzlich Warnungen, wenn das Guthaben zur Neige geht.

Kontrolle in der Konsole: *Billing and Cost Management* → *Budgets*. Ein zweiter Aufruf ändert nichts; zum Ändern erst `./delete-budget.sh`, dann wieder `./create-budget.sh`. Endgültig löschen erst am Kursende.

## Fragen zum Weiterdenken

- Warum ist ein Budget-Alarm keine Kostenbremse? Was passiert bei AWS, wenn das Budget überschritten wird?
- Welche Aufgaben übernimmt AWS im Shared-Responsibility-Modell für das Konto selbst, welche bleiben beim Kunden?
- Wofür ist IAM Identity Center gedacht, und wann lohnt es sich gegenüber einzelnen IAM-Benutzern?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Anmeldung der CLI | `aws login` | `az login` | `gcloud auth login` |
| Budget | AWS Budgets | Cost Management Budgets | Cloud Billing Budgets |
