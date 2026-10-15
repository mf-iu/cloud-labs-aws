# T01 – Konto absichern, CLI und Budget-Alarm

**Ziel:** Ein AWS-Konto im Free Plan, das nicht mit dem Root-Benutzer verwendet wird, eine funktionierende AWS CLI im Dev Container und ein Budget-Alarm, der vor unerwarteten Kosten warnt.

**Kosten:** keine. Budgets mit E-Mail-Benachrichtigung sind kostenlos.

## 1. Konto anlegen (Browser)

Zeitbedarf ca. 20 Minuten. Bereithalten: eine E-Mail-Adresse, zu der es noch kein AWS-Konto gibt, eine Kreditkarte, ein Mobiltelefon und eine Authenticator-App oder einen Passkey.

### 1.1 Registrieren

1. <https://aws.amazon.com/free> öffnen und *Create a free account* wählen.
2. E-Mail-Adresse und Kontonamen eingeben (z. B. `cloud-kurs-<initialen>`), den Bestätigungscode aus der E-Mail eintragen und ein starkes Passwort festlegen. E-Mail-Adresse und Passwort sind die Zugangsdaten des **Root-Benutzers**, der alles darf – im Passwortmanager speichern.
3. Kontotyp **Personal** wählen, die Kontaktdaten eintragen und das AWS Customer Agreement akzeptieren.
4. Die Kreditkarte eingeben. Sie dient der Identitätsprüfung; die Bank zeigt dabei eventuell eine kleine Vormerkung an, die wieder verfällt.
5. Die Telefonnummer bestätigen (Code per SMS oder Anruf).
6. Den Kontoplan **Free** wählen, nicht *Paid*, und als Support-Plan *Basic support – Free*.
7. Auf die E-Mail warten, dass das Konto aktiviert ist – meist wenige Minuten, selten bis zu 24 Stunden.

**Was der Free Plan bedeutet:** 100 USD Guthaben sofort und bis zu 100 USD zusätzlich für Einstiegsaktivitäten, z. B. das Anlegen eines Budgets (Abschnitt 3). Solange das Konto nicht auf den Paid Plan umgestellt wird, entstehen keine Kosten. Der Free Plan endet nach sechs Monaten oder wenn das Guthaben verbraucht ist; dann wird das Konto geschlossen, und AWS löscht die Daten nach 90 Tagen, falls bis dahin nicht auf den Paid Plan umgestellt wurde. Dienste und Funktionen, die das Guthaben schnell aufbrauchen könnten, sind im Free Plan gesperrt. Guthaben und Laufzeit zeigt die Startseite von *Billing and Cost Management*.

**Achtung:** Einige Schritte stellen das Konto automatisch auf den Paid Plan um, u. a. das Anlegen einer Organisation mit AWS Organizations – auch indirekt beim Aktivieren von IAM Identity Center mit AWS Organizations – und eine Landing Zone mit AWS Control Tower. Beides ist im Kurs nicht nötig.

### 1.2 Root-Benutzer absichern

1. Unter <https://console.aws.amazon.com> mit *Root user*, E-Mail-Adresse und Passwort anmelden.
2. **MFA** einrichten: Kontoname oben rechts → *Security credentials* → *Assign MFA device*, dann einen Passkey oder eine Authenticator-App registrieren. AWS verlangt MFA für Root-Benutzer und fordert bei der Anmeldung dazu auf. Ein zweites Gerät als Reserve schützt davor, sich auszusperren.
3. Den IAM-Benutzern die Abrechnungsseiten freigeben: Kontoname → *Account* → bei *IAM User and Role Access to Billing Information* auf *Edit* → **Activate IAM Access** → *Update*. Diese Einstellung kann nur der Root-Benutzer ändern. Ohne sie zeigt die Konsole dem IAM-Benutzer die Abrechnungsseiten nicht an, z. B. Guthaben und Rechnungen; die Skripte der Übungen brauchen sie nicht.

### 1.3 IAM-Benutzer für die tägliche Arbeit

1. *IAM* → *Users* → *Create user*.
2. Als Namen z. B. `admin` eintragen und *Provide user access to the AWS Management Console* aktivieren. Bei der Frage nach der Art des Zugangs **I want to create an IAM user** wählen, nicht Identity Center (siehe *Achtung* oben). Ein eigenes Passwort festlegen; *Users must create a new password at next sign-in* kann ausgeschaltet bleiben.
3. *Attach policies directly* → die Richtlinien `AdministratorAccess` und `SignInLocalDevelopmentAccess` auswählen. Die zweite enthält die Rechte für die Anmeldung der CLI mit `aws login`. `AdministratorAccess` schließt sie zwar ein, aber so bleibt die Anmeldung möglich, falls die Rechte später eingeschränkt werden.
4. *Create user* und die **Console sign-in URL** notieren: `https://<kontonummer>.signin.aws.amazon.com/console`. Lesbarer wird sie mit einem Alias: *IAM* → *Dashboard* → *Account Alias* → *Create*, danach `https://<alias>.signin.aws.amazon.com/console`.
5. Als Root-Benutzer abmelden, über die Sign-in-URL als `admin` anmelden und auch für diesen Benutzer **MFA** einrichten (*Security credentials* → *Assign MFA device*).
6. Region oben rechts auf **Europe (Frankfurt) eu-central-1** stellen.

Ab jetzt nur noch mit dem IAM-Benutzer arbeiten; den Root-Benutzer nur für Konto- und Abrechnungseinstellungen verwenden. Keine Access Keys anlegen – die CLI meldet sich in Abschnitt 2 mit `aws login` an.

## 2. CLI anmelden (Dev Container)

Im Terminal des Dev Containers (siehe [README](../README.md#arbeitsumgebung-dev-container)):

```bash
cd /workspaces/cloud-labs-aws/t01-grundlagen          # Ordner dieser Übung
cp --interactive ../config.example.env ../config.env  # OWNER, ALERT_EMAIL usw. eintragen
aws --version                                         # mindestens 2.32
aws login --remote --region eu-central-1
```

`cp --interactive` fragt nach, falls `config.env` schon existiert (z. B. aus der Einrichtung im [README](../README.md#einrichtung)); dann mit `n` antworten und die vorhandene Datei behalten.

`aws login --remote` gibt eine URL aus. Die URL im Browser öffnen, mit dem IAM-Benutzer anmelden und den angezeigten Code in das Terminal kopieren. Die CLI erhält damit kurzlebige Zugangsdaten, die sie bis zu zwölf Stunden selbst erneuert; es gibt keine dauerhaften Access Keys, die verloren gehen könnten. Danach:

```bash
./check-cli.sh
```

Das Skript zeigt Konto, Benutzer und Region und warnt, wenn die Anmeldung mit dem Root-Benutzer erfolgt ist.

### SSH-Schlüssel für die VMs

Ab Termin 2 melden sich die Skripte per SSH an den VMs an. Den Schlüssel am besten gleich jetzt anlegen – **im Ubuntu-Terminal von WSL, nicht im Terminal des Containers.**

Warum: Der Ordner `~/.ssh` gehört zu WSL. Der Dev Container bindet ihn nur ein, damit die Schlüssel einen Neubau des Containers überstehen; im Container scheitert `ssh-keygen` daran. In WSL gehört der Ordner dem eigenen Benutzer, dort funktioniert es.

1. Das Ubuntu-Terminal öffnen: im Startmenü von Windows *Ubuntu* bzw. *Ubuntu 24.04* oder ein neues Ubuntu-Fenster im Windows-Terminal. Die Eingabeaufforderung zeigt `<benutzer>@<rechner>:~$`, nicht `vscode ➜ /workspaces/…`.
2. Den Schlüssel anlegen:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
   ```

   Die Passphrase darf leer bleiben (zweimal Enter). Gibt es den Schlüssel schon, fragt `ssh-keygen`, ob er überschrieben werden soll – dann mit `n` antworten und den vorhandenen verwenden.
3. Zurück im Container: Der Schlüssel liegt dort sofort unter `/home/vscode/.ssh/id_ed25519`, ein Neustart ist nicht nötig. Prüfen mit `ls ~/.ssh` im Terminal des Containers. `SSH_PUBLIC_KEY` in `config.env` zeigt bereits auf `~/.ssh/id_ed25519.pub`.

## 3. Budget-Alarm

**Wozu:** Ein Budget ist ein Betrag für einen Zeitraum. AWS vergleicht die laufenden Kosten damit und schickt eine E-Mail, sobald eine festgelegte Schwelle erreicht ist. Das ist eine Warnung, keine Bremse – AWS hält dabei keine Ressource an. Im Free Plan kann zwar nichts berechnet werden, aber das Guthaben ist endlich: Ist es aufgebraucht, schließt AWS das Konto. Der Alarm meldet also, wenn eine vergessene Ressource das Guthaben aufzehrt. Nach einer Umstellung auf den Paid Plan wäre er der einzige Hinweis, bevor eine Rechnung entsteht.

```bash
./create-budget.sh
```

**Was das Skript anlegt**

| Einstellung | Wert | Bedeutung |
|---|---|---|
| Name | `pf-<owner>-monthly-budget` | `<owner>` aus `config.env` |
| Art | Kostenbudget, monatlich | beginnt am Monatsersten neu |
| Betrag | `BUDGET_AMOUNT` aus `config.env`, Standard 10 USD | das Skript legt den Betrag in USD an |
| Gutschriften | werden nicht abgezogen | Im Free Plan bezahlt das Guthaben alles. Mit Abzug der Gutschriften bliebe das Budget immer bei 0 USD und würde nie warnen; so zählt es die Kosten, die das Guthaben aufzehren. |
| Alarme | 50 % und 80 % der tatsächlichen Kosten, 100 % der Prognose | bei 10 USD: E-Mail ab 5 USD, ab 8 USD und sobald AWS für den Monat mehr als 10 USD erwartet |
| Empfänger | `ALERT_EMAIL` aus `config.env` | |

**Gut zu wissen**

- **Verzögerung:** AWS aktualisiert die Abrechnungsdaten mindestens einmal am Tag. Ein Alarm kommt daher erst Stunden nach den Kosten – für den Kurs genügt das, weil sich vergessene Ressourcen über Tage summieren.
- **Prognose:** Für Prognosen braucht AWS rund fünf Wochen Nutzungsdaten. Der Prognose-Alarm greift in einem neuen Konto also erst nach etwa fünf Wochen; bis dahin warnen nur die Alarme auf tatsächliche Kosten.
- **Häufigkeit:** Jeder Alarm auf tatsächliche Kosten kommt höchstens einmal im Monat, wenn die Schwelle zum ersten Mal überschritten wird.
- **Kosten:** Budgets ohne automatische Aktionen sind kostenlos. Im Free Plan gehört das Anlegen eines Budgets zu den Aktivitäten, für die AWS zusätzliches Guthaben gutschreibt (Abschnitt 1.1).
- **Weitere Warnungen:** Im Free Plan schickt AWS außerdem E-Mails, wenn das Guthaben zur Neige geht.

**Wenn eine Warnung kommt**

1. `../tools/find-leftovers.sh` ausführen: Es listet die Ressourcen des Kurses und alles, was auch im Leerlauf stündlich kostet.
2. In der Konsole unter *Billing and Cost Management* → *Bills* oder *Cost Explorer* (nach *Service* gruppiert) nachsehen, welcher Dienst die Kosten verursacht. Der Cost Explorer wird beim ersten Öffnen eingerichtet; seine Daten erscheinen erst nach bis zu 24 Stunden.
3. Die Ressourcen mit dem Aufräumskript der jeweiligen Übung löschen und danach `find-leftovers.sh` noch einmal ausführen.

**Kontrolle und Änderungen:** `./check-cli.sh` listet die Budgets des Kontos; in der Konsole stehen sie unter *Billing and Cost Management* → *Budgets* (für den IAM-Benutzer nur mit *Activate IAM Access* aus Abschnitt 1.2). Ein zweiter Aufruf von `./create-budget.sh` ändert nichts. Um Betrag oder E-Mail-Adresse zu ändern, erst `./delete-budget.sh`, dann `config.env` anpassen und wieder `./create-budget.sh`. Endgültig löschen erst am Kursende.

## Fragen zum Weiterdenken

- Warum ist ein Budget-Alarm keine Kostenbremse? Was passiert bei AWS, wenn das Budget überschritten wird?
- Welche Aufgaben übernimmt AWS im Shared-Responsibility-Modell für das Konto selbst, welche bleiben beim Kunden?
- Wofür ist IAM Identity Center gedacht, und wann lohnt es sich gegenüber einzelnen IAM-Benutzern?

## Andere Anbieter

| | AWS | Azure | Google Cloud |
|---|---|---|---|
| Anmeldung der CLI | `aws login` | `az login` | `gcloud auth login` |
| Budget | AWS Budgets | Cost Management Budgets | Cloud Billing Budgets |
