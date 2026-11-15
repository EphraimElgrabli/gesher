<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher : un pont entre les agents IA et les apps de votre Mac" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">Votre IA, voici votre Mac.</h3>

<p align="center">
  Gesher permet à Claude, Codex, Cursor et à toutes les autres apps d'IA compatibles MCP de travailler avec vos apps<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b> et <b>Freeform</b>,<br>
  nativement et en toute confidentialité, directement sur votre Mac. Sans AppleScript, sans Shortcuts, sans clics simulés à l'écran.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Dernière version" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Compatible avec tout client MCP" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="Licence : GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <b>Français</b> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*Cette traduction peut être en retard sur le [README anglais](../../README.md), qui fait foi.*

<p align="center">
  🔒 <b>Gesher tourne entièrement sur votre Mac.</b> Aucun serveur Gesher, aucun compte, aucune télémétrie.
</p>

> [!TIP]
> **Agents IA :** lisez [`llms.txt`](../../llms.txt) pour la carte de ce projet, et
> [`docs/install.md`](../install.md) pour installer Gesher pour votre utilisateur.

## Prêt en une minute

**Le plus simple : demandez à votre agent.** Collez ceci dans Claude Code, Codex, Cursor ou n'importe quel
agent capable d'exécuter des commandes :

```text
Installe Gesher sur mon Mac et connecte-le à mes apps d'IA en suivant
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**Ou faites-le vous-même, en trois étapes :**

**1. Installez.** Une seule ligne dans le Terminal. Elle repère vos apps d'IA et vous demande lesquelles
connecter.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. Dites oui à macOS.** Dans une nouvelle fenêtre de Terminal, lancez `gesher permissions` et cliquez sur
**Autoriser**. Notes et Freeform demandent un simple glisser dans l'Accès complet au disque ; Gesher vous
ouvre la fenêtre.

**3. Demandez.** Redémarrez votre app d'IA et essayez *« Qu'est-ce que j'ai au programme demain ? »*

<p align="center">
  <b>Compatible avec</b><br>
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
  <img alt="tout client MCP" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## Essayez de demander

> *« À quoi ressemble ma semaine ? Trouve-moi deux heures libres pour me concentrer et bloque-les. »*

> *« Transforme ma note **Voyage à Lisbonne** en liste de bagages dans Reminders, pour la veille du vol. »*

> *« Va-t-il pleuvoir pendant mon footing de 18 h ? Si oui, décale-le à demain matin. »*

> *« Qui fête son anniversaire ce mois-ci ? Ajoute des idées de cadeaux dans mes notes. »*

> *« Trouve une pharmacie ouverte en ce moment près de mon prochain rendez-vous, et combien de temps il faut pour y aller à pied. »*

> *« Crée un tableau Freeform pour la rénovation de la cuisine avec les liens de ma note **Cuisine**. »*

| Sans Gesher | Avec Gesher |
|---|---|
| *« Je n'ai pas accès à votre agenda, mais vous pourriez le consulter et me dire… »* | Lit votre agenda, trouve le créneau libre et le réserve. ✅ |
| Vous copiez une note dans le chat, puis recopiez la réponse. | Votre agent lit la note et la modifie sur place, en Markdown. ✅ |
| Vous demandez un rappel ; l'agent vous dit d'ouvrir Reminders. | *« Rappelle-moi d'acheter du lait quand je quitte le bureau. »* C'est fait, avec une alerte de lieu. ✅ |

## Ce que votre agent peut faire

| | App | Votre agent peut… | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | ajouter, cocher et organiser des tâches : listes, sections, tags, sous-tâches, listes intelligentes, modèles | [28 outils](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | lire votre agenda, trouver du temps libre, créer et déplacer des événements, répondre aux invitations | [17 outils](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | retrouver n'importe qui par nom, téléphone ou e-mail, mettre à jour les fiches, groupes, anniversaires | [21 outils](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | lire et écrire des notes en Markdown, avec listes de contrôle, tableaux, tags et pièces jointes | [29 outils](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | chercher des lieux, voir les horaires d'ouverture, planifier itinéraires et temps de trajet | [6 outils](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | consulter la météo partout, heure par heure, plus la qualité de l'air | [10 outils](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | lire vos tableaux, en créer de nouveaux, ajouter textes, liens, images et fichiers | [6 outils](../../apps/freeform/README.md) |

Si vous utilisez iCloud, chaque modification arrive sur votre iPhone et votre iPad, comme si vous l'aviez faite vous-même.

## Ce qui le rend différent

- **Il est vraiment natif.** Gesher appelle les mêmes frameworks macOS (privés) que les apps elles-mêmes.
  Pas d'AppleScript, pas de Raccourcis, pas de clics dans les fenêtres, et les apps n'ont pas besoin d'être
  ouvertes (seul Freeform s'ouvre discrètement en arrière-plan quand votre agent ajoute quelque chose à un tableau).
- **Il est privé.** Aucune inscription, aucune collecte, rien à configurer dans le cloud.
- **Il est soigneux.** Chaque modification est relue pour vérifier qu'elle a bien fonctionné. Les
  suppressions en masse sont sauvegardées d'abord. Les rappels et notes supprimés vont dans Suppressions
  récentes, et les modifications de notes peuvent être liées à la version que l'agent a lue, pour qu'il
  n'écrase jamais un changement qu'il n'a pas vu.
- **Vous gardez la main.** macOS vous demande votre accord pour chaque app, et vous pouvez confier votre
  Calendar à un agent sans vos Contacts.
- **Il parle agent.** Des noms plutôt que des ids, des dates comme *"next tuesday 14:00"*, et des erreurs
  qui disent quoi faire ensuite, pour que les agents y arrivent en moins d'essais.

## C'est aussi un CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

Du JSON compact pour les scripts et les agents, `--format pretty` pour les humains. `<app>-cli --help` explique le reste.

## Connectez d'autres apps d'IA plus tard

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

Vous préférez le faire à la main, ou vous utilisez un outil absent de la liste ? Chaque app est un serveur
MCP standard (`reminders-cli mcp`, `calendar-cli mcp`, …) : [configuration pour chaque app d'IA](../clients.md).

## FAQ

<details>
<summary><b>Mes données sont-elles envoyées quelque part ?</b></summary>

Pas par Gesher. Il tourne sur votre Mac et n'a pas de serveurs. Weather et Maps interrogent les services
d'Apple, exactement comme ces apps. Ce que vous partagez avec un agent IA part chez son fournisseur, comme
tout ce que vous lui écrivez ; avec un modèle local dans LM Studio ou opencode, votre conversation ne
quitte jamais votre Mac.
</details>

<details>
<summary><b>Est-ce prudent de laisser un agent modifier mes affaires ?</b></summary>

Gesher est soigneux (les modifications sont vérifiées, les suppressions en masse sont sauvegardées dans
`~/.config/gesher/backups`, les rappels et notes supprimés vont dans Suppressions récentes), mais il fait
ce que votre agent lui demande. Ne connectez que les apps dont vous avez besoin, et gardez un œil sur ce
que vous laissez un agent modifier.
</details>

<details>
<summary><b>De quoi ai-je besoin ?</b></summary>

D'un Mac avec Apple silicon et macOS 26 ou ultérieur. Gesher est testé sur macOS 27 ; macOS 26 devrait fonctionner
mais n'a pas encore été testé. Les Mac Intel ne sont pas pris en charge. Pas besoin de Xcode.
</details>

<details>
<summary><b>Qu'est-ce qu'il ne sait pas faire ?</b></summary>

Les notes des contacts et certaines modifications dans Freeform (formes,
notes adhésives, renommage de tableaux) sont réservés par macOS aux apps d'Apple. Maps est en lecture
seule. [Liste complète](../limitations.md).
</details>

<details>
<summary><b>Pourquoi l'installateur me demande-t-il mon mot de passe ?</b></summary>

Uniquement pour créer un certificat de signature sur votre Mac, afin que les mises à jour conservent les
autorisations que vous avez accordées. Si vous refusez, Gesher fonctionne quand même ; il faudra simplement
redonner l'accès après les mises à jour.
</details>

<details>
<summary><b>Quelle différence avec les serveurs MCP basés sur AppleScript ?</b></summary>

AppleScript ne voit que ce que chaque app a choisi de rendre scriptable, a besoin que l'app soit ouverte et
demande l'accès à l'Automatisation. Gesher appelle les frameworks sur lesquels les apps sont construites :
il est plus rapide, fonctionne apps fermées et atteint ce que les scripts ne peuvent pas, comme les sections
et listes intelligentes de Reminders, les tags et tableaux de Notes, et les tableaux Freeform.
</details>

<details>
<summary><b>Puis-je faire confiance au téléchargement ?</b></summary>

Chaque version est compilée à partir du commit tagué de ce dépôt et publiée avec un fichier `.sha256`. L'installateur
contrôle le SHA-256 du téléchargement. Les outils ne sont pas notarisés par Apple ; c'est l'installateur
qui les signe sur votre Mac. Les [notes de sécurité](../../SECURITY.md) expliquent ce contre quoi les
autorisations de Gesher vous protègent.
</details>

<details>
<summary><b>Une mise à jour de macOS va-t-elle le casser ?</b></summary>

C'est possible : Gesher utilise des parties de macOS qu'Apple ne s'engage pas à garder stables. Si quelque
chose change, Gesher s'arrête avec un message clair au lieu de deviner, et `gesher doctor` montre ce qui est touché.
</details>

<details>
<summary><b>Comment le mettre à jour ou le supprimer ?</b></summary>

`gesher update` installe la dernière version en conservant vos autorisations et vos connexions. `gesher uninstall`
supprime Gesher et le déconnecte de vos apps d'IA.
</details>

<details>
<summary><b>Que veut dire « Gesher » ?</b></summary>

C'est le mot hébreu pour *pont* (גשר), et ça se prononce *GUÈ-chèr*.
</details>

## Comment ça marche

Chaque app du Mac a son petit outil en ligne de commande, qui est aussi un serveur
[MCP](https://modelcontextprotocol.io). Il charge le framework sur lequel l'app elle-même est construite et
l'appelle directement, si bien que chaque modification suit le même chemin que si vous l'aviez faite dans
l'app. Une seule déclaration par action devient la commande du CLI, son aide, l'outil MCP et son schéma :
ils ne peuvent jamais diverger.

En savoir plus : [architecture](../architecture.md) · [autorisations](../permissions.md) ·
[configuration des apps d'IA](../clients.md) · [guide d'installation pour agents](../install.md) · [contribuer dans un fork](../../AGENTS.md)

## À propos de ce projet

Gesher est un projet personnel, partagé tel quel. Il est expérimental et sans support : les issues et les
pull requests sont fermées pour qu'il reste petit. Vous êtes chaleureusement invité à le forker et à vous
l'approprier. Les signalements de sécurité sont les bienvenus via le [signalement privé](../../SECURITY.md).

Si Gesher rend votre Mac un peu plus magique, une ⭐ aide d'autres personnes à le découvrir.

<sub>Gesher est un projet indépendant, ni affilié à Apple Inc. ni approuvé par elle. Apple, Mac, macOS,
iCloud et les noms des apps sont des marques d'Apple Inc., utilisées uniquement pour indiquer avec quelles
apps Gesher fonctionne. Gesher ne contient aucun code ni visuel d'Apple. [Mentions légales](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
