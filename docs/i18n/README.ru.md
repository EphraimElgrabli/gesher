<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher — мост между ИИ-агентами и приложениями на вашем Mac" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">Ваш ИИ, знакомьтесь: ваш Mac.</h3>

<p align="center">
  Gesher позволяет Claude, Codex, Cursor и любому другому ИИ-приложению с поддержкой MCP работать с вашими<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b> и <b>Freeform</b>,<br>
  нативно и приватно, прямо на вашем Mac. Без AppleScript, без Shortcuts, без кликов по экрану.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Последний релиз" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Работает с любым MCP-клиентом" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="Лицензия: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
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
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <b>Русский</b>
  </sub>
</p>

*Этот перевод может отставать от [английского README](../../README.md), который считается основным.*

<p align="center">
  🔒 <b>Сам Gesher работает целиком на вашем Mac.</b> Никаких серверов Gesher, аккаунтов и телеметрии.
</p>

> [!TIP]
> **ИИ-агентам:** карта проекта лежит в [`llms.txt`](../../llms.txt), а в
> [`docs/install.md`](../install.md) написано, как установить Gesher для вашего пользователя.

## Начните за минуту

**Самый простой способ: попросите агента.** Вставьте это в Claude Code, Codex, Cursor или любой агент,
который умеет запускать команды:

```text
Установи Gesher на мой Mac и подключи его к моим ИИ-приложениям по инструкции
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**Или сами, в три шага:**

**1. Установите.** Одна строка в Terminal. Установщик найдёт ваши ИИ-приложения и спросит, какие
подключить.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. Скажите macOS «да».** В новом окне Terminal выполните `gesher permissions` и нажмите **Allow**. Notes
и Freeform нужно один раз перетащить в Full Disk Access — нужное окно Gesher откроет сам.

**3. Спросите.** Перезапустите ИИ-приложение и попробуйте: *«Что у меня завтра в календаре?»*

<p align="center">
  <b>Работает с</b><br>
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
  <img alt="любой MCP-клиент" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## Попробуйте спросить

> *«Как выглядит моя неделя? Найди два свободных часа для спокойной работы и забронируй их.»*

> *«Преврати заметку **Поездка в Лиссабон** в список вещей в Reminders, со сроком за день до вылета.»*

> *«Будет ли дождь во время моей пробежки в 18:00? Если да, перенеси её на завтрашнее утро.»*

> *«У кого день рождения в этом месяце? Добавь идеи подарков в мои заметки.»*

> *«Найди аптеку, которая открыта прямо сейчас, рядом с местом моей следующей встречи, и сколько туда идти пешком.»*

> *«Сделай доску Freeform для ремонта кухни со ссылками из моей заметки **Кухня**.»*

| Без Gesher | С Gesher |
|---|---|
| *«У меня нет доступа к вашему календарю, но вы можете проверить его и рассказать мне…»* | Читает ваше расписание, находит свободное окно и бронирует его. ✅ |
| Вы копируете заметку в чат, а потом ответ обратно. | Агент сам читает заметку и правит её на месте, в Markdown. ✅ |
| Просите напоминание, а агент предлагает открыть Reminders. | *«Напомни купить молоко, когда я выйду из офиса.»* Готово, с напоминанием по геопозиции. ✅ |

## Что умеет ваш агент

| | Приложение | Ваш агент может… | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | добавлять, выполнять и упорядочивать задачи: списки, разделы, теги, подзадачи, смарт-списки, шаблоны | [28 инструментов](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | читать расписание, искать свободное время, создавать и переносить события, отвечать на приглашения | [17 инструментов](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | находить кого угодно по имени, телефону или почте, обновлять карточки, группы, дни рождения | [21 инструмент](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | читать и писать заметки в Markdown, с чек-листами, таблицами, тегами и вложениями | [29 инструментов](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | искать места, смотреть часы работы, прокладывать маршруты и считать время в пути | [6 инструментов](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | смотреть прогноз где угодно, по часам, плюс качество воздуха | [10 инструментов](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | читать ваши доски, создавать новые, добавлять текст, ссылки, изображения и файлы | [6 инструментов](../../apps/freeform/README.md) |

Если вы пользуетесь iCloud, каждое изменение появится на iPhone и iPad, как будто вы сделали его сами.

## Чем он особенный

- **Он по-настоящему нативный.** Gesher вызывает те же (приватные) фреймворки macOS, что и сами
  приложения. Никакого AppleScript, никаких Shortcuts, никаких кликов по окнам — и приложения не нужно
  открывать (только Freeform тихо открывается в фоне, когда ваш агент добавляет что-то на доску).
- **Он приватный.** Не нужно нигде регистрироваться, ничего не собирается, ничего не надо настраивать в облаке.
- **Он аккуратный.** Каждое изменение перечитывается, чтобы убедиться, что всё получилось. Перед
  массовым удалением делается резервная копия. Удалённые напоминания и заметки попадают в Recently
  Deleted, а правку заметки можно привязать к версии, которую прочитал агент, — так он никогда не
  затрёт изменение, которого не видел.
- **Всё под вашим контролем.** macOS спрашивает разрешение для каждого приложения отдельно, и можно дать
  агенту Calendar, не давая Contacts.
- **Он говорит на языке агентов.** Имена вместо id, даты вроде *"next tuesday 14:00"* и ошибки, которые
  объясняют, что делать дальше, — так агенты справляются с меньшего числа попыток.

## А ещё это CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

Компактный JSON для скриптов и агентов, `--format pretty` для людей. Остальное расскажет `<app>-cli --help`.

## Подключайте новые ИИ-приложения когда угодно

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

Хотите вручную или пользуетесь чем-то, чего нет в списке? Каждое приложение — это стандартный MCP-сервер
(`reminders-cli mcp`, `calendar-cli mcp`, …): [настройка для любого ИИ-приложения](../clients.md).

## Вопросы и ответы

<details>
<summary><b>Мои данные куда-то отправляются?</b></summary>

Не через Gesher. Он работает на вашем Mac, и серверов у него нет. Weather и Maps обращаются к сервисам
Apple — ровно так же, как сами эти приложения. То, чем вы делитесь с ИИ-агентом, уходит его провайдеру,
как и всё, что вы ему пишете; с локальной моделью в LM Studio или opencode разговор вообще не покидает
ваш Mac.
</details>

<details>
<summary><b>Безопасно ли разрешать агенту что-то менять?</b></summary>

Gesher осторожен (изменения проверяются, перед массовым удалением создаётся копия в
`~/.config/gesher/backups`, удалённые напоминания и заметки попадают в Recently Deleted), но он делает
то, о чём просит агент. Подключайте только нужные приложения и следите за тем, что вы разрешаете агенту
менять.
</details>

<details>
<summary><b>Что для этого нужно?</b></summary>

Mac на Apple silicon с macOS 26 или новее. Gesher протестирован на macOS 27; на macOS 26 он должен работать, но
ещё не тестировался. Mac на Intel не поддерживаются. Xcode не нужен.
</details>

<details>
<summary><b>Чего он не умеет?</b></summary>

Заметки в контактах и часть правок во Freeform (фигуры, стикеры,
переименование досок) macOS оставляет только приложениям самой Apple. Maps — только для чтения.
[Полный список](../limitations.md).
</details>

<details>
<summary><b>Зачем установщику мой пароль?</b></summary>

Только чтобы создать на вашем Mac сертификат подписи — тогда после обновлений выданные разрешения
сохранятся. Откажетесь — Gesher всё равно будет работать, просто после обновлений доступ придётся
выдать заново.
</details>

<details>
<summary><b>Чем это отличается от MCP-серверов на AppleScript?</b></summary>

AppleScript видит только то, что каждое приложение решило открыть для скриптов, требует, чтобы
приложение было запущено, и просит доступ к Automation. Gesher вызывает фреймворки, на которых построены
сами приложения: он быстрее, работает с закрытыми приложениями и достаёт то, до чего скрипты не
дотягиваются, — разделы и смарт-списки в Reminders, теги и таблицы в Notes, доски во Freeform.
</details>

<details>
<summary><b>Можно ли доверять загрузке?</b></summary>

Каждый релиз собирается из помеченного тегом коммита этого репозитория и публикуется вместе с файлом `.sha256`. Установщик сверяет SHA-256 загруженного файла. Инструменты не нотаризованы Apple — вместо этого
установщик подписывает их прямо на вашем Mac. В [заметках о безопасности](../../SECURITY.md) объясняется,
от чего защищают разрешения Gesher.
</details>

<details>
<summary><b>Не сломается ли он после обновления macOS?</b></summary>

Может: Gesher использует части macOS, стабильность которых Apple не гарантирует. Если что-то изменится,
Gesher остановится с понятным сообщением, а не будет гадать, а `gesher doctor` покажет, что затронуто.
</details>

<details>
<summary><b>Как обновить или удалить?</b></summary>

`gesher update` ставит последнюю версию и сохраняет ваши разрешения и подключения. `gesher uninstall`
удаляет Gesher и отключает его от ваших ИИ-приложений.
</details>

<details>
<summary><b>Что значит «Gesher»?</b></summary>

На иврите это *мост* (גשר), а произносится *ГЕ-шер*.
</details>

## Как это работает

Каждое приложение Mac получает небольшую консольную утилиту, которая одновременно является
[MCP](https://modelcontextprotocol.io)-сервером. Она загружает фреймворк, на котором построено само
приложение, и вызывает его напрямую, поэтому любое изменение проходит тот же путь, как если бы вы
сделали его в приложении. Одно описание на каждое действие превращается в команду CLI, её справку,
инструмент MCP и его схему, так что они никогда не расходятся.

Подробнее: [архитектура](../architecture.md) · [разрешения](../permissions.md) ·
[настройка ИИ-приложений](../clients.md) · [гид по установке для агентов](../install.md) · [как развивать свой форк](../../AGENTS.md)

## О проекте

Gesher — личный проект, которым я делюсь как есть. Он экспериментальный, и поддержки нет: issues и pull
requests закрыты, чтобы проект оставался небольшим. Зато вы очень приглашены сделать форк и превратить
его в свой. Сообщения о проблемах безопасности принимаются через [приватный канал](../../SECURITY.md).

Если с Gesher ваш Mac стал чуточку волшебнее, ⭐ поможет другим его найти.

<sub>Gesher — независимый проект, не связанный с Apple Inc. и не одобренный ею. Apple, Mac, macOS, iCloud
и названия приложений — товарные знаки Apple Inc., упомянутые лишь для того, чтобы указать, с какими
приложениями работает Gesher. Gesher не содержит кода или графики Apple. [Юридические сведения](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
