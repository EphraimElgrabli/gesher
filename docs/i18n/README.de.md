<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher — eine Brücke zwischen KI-Agenten und den Apps auf deinem Mac" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">Deine KI, darf ich vorstellen: dein Mac.</h3>

<p align="center">
  Mit Gesher arbeiten Claude, Codex, Cursor und jede andere MCP-fähige KI-App mit deinen<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b> und <b>Freeform</b>,<br>
  nativ und privat, direkt auf deinem Mac. Ohne AppleScript, ohne Shortcuts, ohne Klicken auf dem Bildschirm.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Neueste Version" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Funktioniert mit jedem MCP-Client" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="Lizenz: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <b>Deutsch</b> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*Diese Übersetzung kann hinter der [englischen README](../../README.md) zurückliegen; maßgeblich ist die englische Fassung.*

<p align="center">
  🔒 <b>Gesher selbst läuft komplett auf deinem Mac.</b> Keine Gesher-Server, keine Accounts, keine Telemetrie.
</p>

> [!TIP]
> **KI-Agenten:** In [`llms.txt`](../../llms.txt) findet ihr die Übersicht über dieses Projekt, und in
> [`docs/install.md`](../install.md), wie ihr Gesher für euren Nutzer einrichtet.

## In einer Minute startklar

**Ganz einfach: Frag deinen Agenten.** Füge das in Claude Code, Codex, Cursor oder einen anderen Agenten
ein, der Befehle ausführen kann:

```text
Installiere Gesher auf meinem Mac und verbinde es mit meinen KI-Apps, wie hier beschrieben:
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**Oder selbst gemacht, in drei Schritten:**

**1. Installieren.** Eine Zeile im Terminal. Sie findet deine KI-Apps und fragt, welche verbunden werden
sollen.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. macOS zustimmen.** Führe in einem neuen Terminal-Fenster `gesher permissions` aus und klick auf
**Allow**. Notes und Freeform brauchen einmal Ziehen in Full Disk Access; Gesher öffnet dir das Fenster.

**3. Fragen.** Starte deine KI-App neu und probier *„Was steht morgen in meinem Kalender?“*

<p align="center">
  <b>Funktioniert mit</b><br>
  <img alt="Claude Desktop" src="https://img.shields.io/badge/Claude_Desktop-1F2328?style=flat-square&logo=claude&logoColor=white">
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-1F2328?style=flat-square&logo=claude&logoColor=white">
  <img alt="Codex" src="https://img.shields.io/badge/Codex-1F2328?style=flat-square">
  <img alt="Cursor" src="https://img.shields.io/badge/Cursor-1F2328?style=flat-square&logo=cursor&logoColor=white">
  <img alt="VS Code · Copilot" src="https://img.shields.io/badge/VS_Code_%C2%B7_Copilot-1F2328?style=flat-square&logo=githubcopilot&logoColor=white">
  <img alt="Windsurf" src="https://img.shields.io/badge/Windsurf-1F2328?style=flat-square&logo=windsurf&logoColor=white">
  <img alt="Gemini CLI" src="https://img.shields.io/badge/Gemini_CLI-1F2328?style=flat-square&logo=googlegemini&logoColor=white">
  <img alt="Antigravity" src="https://img.shields.io/badge/Antigravity-1F2328?style=flat-square">
  <img alt="LM Studio" src="https://img.shields.io/badge/LM_Studio-1F2328?style=flat-square&logo=lmstudio&logoColor=white">
  <img alt="opencode" src="https://img.shields.io/badge/opencode-1F2328?style=flat-square&logo=opencode&logoColor=white">
  <img alt="Zed" src="https://img.shields.io/badge/Zed-1F2328?style=flat-square&logo=zedindustries&logoColor=white">
  <img alt="Kiro" src="https://img.shields.io/badge/Kiro-1F2328?style=flat-square">
  <img alt="Warp" src="https://img.shields.io/badge/Warp-1F2328?style=flat-square&logo=warp&logoColor=white">
  <img alt="Cline" src="https://img.shields.io/badge/Cline-1F2328?style=flat-square&logo=cline&logoColor=white">
  <img alt="jeder MCP-Client" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## Probier mal

> *„Wie sieht meine Woche aus? Such mir zwei freie Stunden für konzentriertes Arbeiten und blockier sie.“*

> *„Mach aus meiner Notiz **Lissabon-Reise** eine Packliste in Reminders, fällig am Tag vor dem Flug.“*

> *„Regnet es bei meinem Lauf um 18 Uhr? Wenn ja, verschieb ihn auf morgen früh.“*

> *„Wer hat diesen Monat Geburtstag? Schreib Geschenkideen in meine Notizen.“*

> *„Finde eine Apotheke in der Nähe meines nächsten Termins, die jetzt offen hat, und wie lange ich zu Fuß brauche.“*

> *„Leg ein Freeform-Board für die Küchenrenovierung an, mit den Links aus meiner Notiz **Küche**.“*

| Ohne Gesher | Mit Gesher |
|---|---|
| *„Ich habe keinen Zugriff auf deinen Kalender, aber du könntest nachsehen und mir sagen …“* | Liest deine Termine, findet die freie Lücke und trägt sie ein. ✅ |
| Du kopierst eine Notiz in den Chat und die Antwort wieder zurück. | Dein Agent liest die Notiz und bearbeitet sie direkt, als Markdown. ✅ |
| Du bittest um eine Erinnerung, und der Agent sagt dir, du sollst Reminders öffnen. | *„Erinnere mich daran, Milch zu kaufen, wenn ich das Büro verlasse.“* Erledigt, mit Ortserinnerung. ✅ |

## Was dein Agent kann

| | App | Dein Agent kann … | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | Aufgaben anlegen, abhaken und ordnen: Listen, Abschnitte, Tags, Unteraufgaben, intelligente Listen, Vorlagen | [28 Tools](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | deine Termine lesen, freie Zeit finden, Events anlegen und verschieben, auf Einladungen antworten | [17 Tools](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | jeden per Name, Telefon oder E-Mail finden, Karten, Gruppen und Geburtstage pflegen | [21 Tools](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | Notizen als Markdown lesen und schreiben, mit Checklisten, Tabellen, Tags und Anhängen | [29 Tools](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | Orte suchen, Öffnungszeiten sehen, Routen und Reisezeiten planen | [6 Tools](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | die Vorhersage für jeden Ort abrufen, Stunde für Stunde, dazu die Luftqualität | [10 Tools](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | deine Boards lesen, neue anlegen, Text, Links, Bilder und Dateien hinzufügen | [6 Tools](../../apps/freeform/README.md) |

Wenn du iCloud nutzt, landet jede Änderung auch auf deinem iPhone und iPad, ganz so, als hättest du sie selbst gemacht.

## Was es besonders macht

- **Wirklich nativ.** Gesher nutzt dieselben (privaten) macOS-Frameworks wie die Apps selbst. Kein
  AppleScript, keine Shortcuts, kein Herumklicken in Fenstern, und die Apps müssen nicht geöffnet sein (nur
  Freeform öffnet sich still im Hintergrund, wenn dein Agent etwas zu einem Board hinzufügt).
- **Privat.** Keine Anmeldung, keine Datensammlung, nichts in der Cloud einzurichten.
- **Sorgfältig.** Jede Änderung wird zurückgelesen, um sicherzugehen, dass sie geklappt hat. Vor
  Massenlöschungen wird ein Backup angelegt. Gelöschte Erinnerungen und Notizen landen in Recently
  Deleted, und Notiz-Änderungen lassen sich an die Version binden, die der Agent gelesen hat, damit er
  nie eine Änderung überschreibt, die er nicht gesehen hat.
- **Du behältst die Kontrolle.** macOS fragt für jede App einzeln nach deiner Erlaubnis, und du kannst
  einem Agenten deinen Calendar geben, ohne ihm deine Contacts zu geben.
- **Es spricht Agentisch.** Namen statt IDs, Datumsangaben wie *"next tuesday 14:00"* und Fehlermeldungen,
  die sagen, was als Nächstes zu tun ist, damit Agenten es mit weniger Versuchen richtig machen.

## Auch als CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

Kompaktes JSON für Skripte und Agenten, `--format pretty` für Menschen. `<app>-cli --help` erklärt den Rest.

## Später weitere KI-Apps verbinden

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

Lieber von Hand, oder nutzt du etwas, das nicht in der Liste steht? Jede App ist ein ganz normaler MCP-Server
(`reminders-cli mcp`, `calendar-cli mcp`, …): [Einrichtung für jede KI-App](../clients.md).

## FAQ

<details>
<summary><b>Werden meine Daten irgendwohin geschickt?</b></summary>

Nicht von Gesher. Es läuft auf deinem Mac und hat keine Server. Weather und Maps fragen Apples Dienste an,
genau wie diese Apps selbst. Was du mit einem KI-Agenten teilst, geht an dessen Anbieter, wie alles, was
du dort eintippst; mit einem lokalen Modell in LM Studio oder opencode verlässt dein Gespräch deinen Mac nie.
</details>

<details>
<summary><b>Ist es sicher, einen Agenten meine Sachen ändern zu lassen?</b></summary>

Gesher ist vorsichtig (Änderungen werden überprüft, Massenlöschungen werden nach `~/.config/gesher/backups`
gesichert, gelöschte Erinnerungen und Notizen landen in Recently Deleted), aber es tut, worum dein Agent
bittet. Verbinde nur die Apps, die du brauchst, und behalte im Blick, was du einen Agenten ändern lässt.
</details>

<details>
<summary><b>Was brauche ich?</b></summary>

Einen Mac mit Apple silicon und macOS 26 oder neuer. Gesher ist auf macOS 27 getestet; macOS 26 sollte funktionieren,
wurde aber noch nicht getestet. Intel-Macs werden nicht
unterstützt. Xcode ist nicht nötig.
</details>

<details>
<summary><b>Was kann es nicht?</b></summary>

Notizen in Kontakten und manche Freeform-Bearbeitungen (Formen, Haftnotizen,
Boards umbenennen) behält macOS Apples eigenen Apps vor. Maps ist nur lesend. [Vollständige Liste](../limitations.md).
</details>

<details>
<summary><b>Warum fragt der Installer nach meinem Passwort?</b></summary>

Nur, um auf deinem Mac ein Signaturzertifikat zu erstellen, damit deine erteilten Berechtigungen bei
Updates erhalten bleiben. Sagst du nein, funktioniert Gesher trotzdem; du erteilst den Zugriff dann nach
Updates einfach erneut.
</details>

<details>
<summary><b>Was ist anders als bei MCP-Servern auf AppleScript-Basis?</b></summary>

AppleScript sieht nur, was die jeweilige App für Skripte freigibt, braucht die App geöffnet und fragt nach
Automation-Zugriff. Gesher nutzt die Frameworks, auf denen die Apps selbst aufbauen: Es funktioniert
bei geschlossenen Apps und erreicht, was Skripte nicht können, etwa Abschnitte und
intelligente Listen in Reminders, Tags und Tabellen in Notes und Boards in Freeform.
</details>

<details>
<summary><b>Kann ich dem Download vertrauen?</b></summary>

Jedes Release wird aus dem getaggten Commit dieses Repositorys gebaut und mit einer `.sha256`-Datei veröffentlicht. Der Installer
kontrolliert die SHA-256-Prüfsumme des Downloads. Die Tools sind nicht von Apple notarisiert; stattdessen
signiert der Installer sie auf deinem Mac. Die [Sicherheitshinweise](../../SECURITY.md) erklären, wovor
dich die Berechtigungen von Gesher schützen.
</details>

<details>
<summary><b>Macht ein macOS-Update es kaputt?</b></summary>

Kann sein: Gesher nutzt Teile von macOS, deren Stabilität Apple nicht zusagt. Ändert sich etwas, stoppt
Gesher mit einer klaren Meldung, statt zu raten, und `gesher doctor` zeigt, was betroffen ist.
</details>

<details>
<summary><b>Wie aktualisiere oder entferne ich es?</b></summary>

`gesher update` installiert die neueste Version und behält deine Berechtigungen und Verbindungen. `gesher uninstall`
entfernt Gesher und trennt es von deinen KI-Apps.
</details>

<details>
<summary><b>Was bedeutet „Gesher“?</b></summary>

Es ist Hebräisch für *Brücke* (גשר) und wird *GEH-scher* ausgesprochen.
</details>

## So funktioniert's

Jede Mac-App bekommt ein kleines Kommandozeilen-Tool, das zugleich ein [MCP](https://modelcontextprotocol.io)-Server
ist. Es lädt das Framework, auf dem die App selbst aufbaut, und ruft es direkt auf, sodass jede Änderung
denselben Weg nimmt, als hättest du sie in der App gemacht. Aus einer einzigen Deklaration pro Aktion
entstehen der CLI-Befehl, seine Hilfe, das MCP-Tool und sein Schema, damit sie nie auseinanderlaufen.

Mehr dazu: [Architektur](../architecture.md) · [Berechtigungen](../permissions.md) ·
[KI-Apps einrichten](../clients.md) · [Installationsanleitung für Agenten](../install.md) · [In einem Fork mitarbeiten](../../AGENTS.md)

## Über dieses Projekt

Gesher ist experimentell und wird gepflegt. Fehlerberichte sind willkommen, besonders wenn ein macOS-Update
etwas kaputt macht: öffne ein [Issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose) mit deiner macOS-Version, der App und der Ausgabe von
`gesher doctor`. Pull Requests sind willkommen, werden aber langsam geprüft. Fragen und Ideen gehören in die
[Discussions](https://github.com/EphraimElgrabli/gesher/discussions). Sicherheitsmeldungen bitte über die [private Meldung](../../SECURITY.md).

Wenn Gesher deinen Mac ein bisschen magischer macht, hilft ein ⭐ anderen, es zu finden.

<sub>Gesher ist ein unabhängiges Projekt, nicht mit Apple Inc. verbunden und nicht von Apple unterstützt.
Apple, Mac, macOS, iCloud und die App-Namen sind Marken von Apple Inc. und werden nur genannt, um zu sagen,
mit welchen Apps Gesher funktioniert. Gesher enthält keinen Code und keine Grafiken von Apple.
[Rechtliche Hinweise](../legal.md) · [GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
