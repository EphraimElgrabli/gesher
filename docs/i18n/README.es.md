<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher: un puente entre los agentes de IA y las apps de tu Mac" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">Tu IA, te presento a tu Mac.</h3>

<p align="center">
  Gesher permite que Claude, Codex, Cursor y cualquier otra app de IA compatible con MCP trabajen con tus apps<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b> y <b>Freeform</b>,<br>
  de forma nativa y privada, directamente en tu Mac. Sin AppleScript, sin Shortcuts, sin clics simulados en la pantalla.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Última versión" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Funciona con cualquier cliente MCP" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="Licencia: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <b>Español</b> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*Esta traducción puede ir por detrás del [README en inglés](../../README.md), que es la versión de referencia.*

<p align="center">
  🔒 <b>Gesher funciona íntegramente en tu Mac.</b> Sin servidores de Gesher, sin cuentas, sin telemetría.
</p>

> [!TIP]
> **Agentes de IA:** lean [`llms.txt`](../../llms.txt) para ver el mapa de este proyecto, y
> [`docs/install.md`](../install.md) para instalar Gesher para su usuario.

## Empieza en un minuto

**Lo más fácil: pídeselo a tu agente.** Pega esto en Claude Code, Codex, Cursor o cualquier agente que
pueda ejecutar comandos:

```text
Instala Gesher en mi Mac y conéctalo a mis apps de IA siguiendo
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**O hazlo tú, en tres pasos:**

**1. Instala.** Una sola línea en Terminal. Encuentra tus apps de IA y te pregunta cuáles conectar.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. Dile que sí a macOS.** En una nueva ventana de Terminal, ejecuta `gesher permissions` y haz clic en
**Permitir**. Notes y Freeform necesitan que las arrastres una vez a Acceso total al disco; Gesher te abre
la ventana.

**3. Pregunta.** Reinicia tu app de IA y prueba con *"¿Qué tengo mañana en el calendario?"*

<p align="center">
  <b>Funciona con</b><br>
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
  <img alt="cualquier cliente MCP" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## Prueba a pedirle

> *"¿Cómo tengo la semana? Búscame dos horas libres para concentrarme y resérvalas."*

> *"Convierte mi nota del **viaje a Lisboa** en una lista de equipaje en Reminders, para el día antes del vuelo."*

> *"¿Va a llover mientras salgo a correr a las 6 de la tarde? Si es así, pásalo a mañana por la mañana."*

> *"¿Quién cumple años este mes? Añade ideas de regalo a mis notas."*

> *"Encuentra una farmacia abierta ahora cerca de mi próxima reunión y dime cuánto se tarda a pie."*

> *"Crea un tablero de Freeform para la reforma de la cocina con los enlaces de mi nota **Cocina**."*

| Sin Gesher | Con Gesher |
|---|---|
| *"No tengo acceso a tu calendario, pero podrías mirarlo y decírmelo…"* | Lee tu agenda, encuentra el hueco libre y lo reserva. ✅ |
| Copias una nota en el chat y luego copias la respuesta de vuelta. | Tu agente lee la nota y la edita directamente, en Markdown. ✅ |
| Pides un recordatorio y el agente te dice que abras Reminders. | *"Recuérdame comprar leche cuando salga de la oficina."* Hecho, con aviso por ubicación. ✅ |

## Lo que puede hacer tu agente

| | App | Tu agente puede… | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | añadir, completar y organizar tareas: listas, secciones, etiquetas, subtareas, listas inteligentes, plantillas | [28 herramientas](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | leer tu agenda, encontrar tiempo libre, crear y mover eventos, responder invitaciones | [17 herramientas](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | encontrar a cualquiera por nombre, teléfono o email, actualizar fichas, grupos, cumpleaños | [21 herramientas](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | leer y escribir notas en Markdown, con listas de verificación, tablas, etiquetas y adjuntos | [29 herramientas](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | buscar lugares, ver horarios, planificar rutas y tiempos de trayecto | [6 herramientas](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | consultar el pronóstico de cualquier lugar, hora a hora, y la calidad del aire | [10 herramientas](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | leer tus tableros, crear otros nuevos, añadir texto, enlaces, imágenes y archivos | [6 herramientas](../../apps/freeform/README.md) |

Si usas iCloud, cada cambio llega a tu iPhone y a tu iPad, como si lo hubieras hecho tú.

## Qué lo hace diferente

- **Es nativo de verdad.** Gesher llama a los mismos frameworks (privados) de macOS que usan las propias
  apps. Nada de AppleScript, ni Atajos, ni clics por las ventanas, y las apps no tienen que estar abiertas
  (solo Freeform se abre discretamente en segundo plano cuando tu agente añade algo a un tablero).
- **Es privado.** Nada en lo que registrarte, nada que se recopile, nada que configurar en la nube.
- **Es cuidadoso.** Cada cambio se vuelve a leer para comprobar que ha funcionado. Antes de un borrado
  masivo se hace una copia de seguridad. Los recordatorios y las notas borrados van a Eliminados
  recientemente, y las ediciones de notas pueden ligarse a la versión que leyó el agente, para que nunca
  sobrescriba un cambio que no ha visto.
- **Tú tienes el control.** macOS te pide permiso para cada app, y puedes darle a un agente tu Calendar
  sin tus Contacts.
- **Habla el idioma de los agentes.** Nombres en vez de ids, fechas como *"next tuesday 14:00"* y errores
  que dicen qué hacer a continuación, para que los agentes acierten con menos intentos.

## También es un CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

JSON compacto para scripts y agentes, `--format pretty` para personas. `<app>-cli --help` te cuenta el resto.

## Conecta más apps de IA cuando quieras

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

¿Prefieres hacerlo a mano, o usas algo que no aparece en la lista? Cada app es un servidor MCP estándar
(`reminders-cli mcp`, `calendar-cli mcp`, …): [configuración para cada app de IA](../clients.md).

## Preguntas frecuentes

<details>
<summary><b>¿Se envían mis datos a algún sitio?</b></summary>

Gesher no envía nada. Funciona en tu Mac y no tiene servidores. Weather y Maps consultan los servicios de
Apple, exactamente como lo hacen esas apps. Lo que compartas con un agente de IA llega a su proveedor,
como cualquier cosa que le escribas; con un modelo local en LM Studio u opencode, tu conversación nunca
sale de tu Mac.
</details>

<details>
<summary><b>¿Es seguro dejar que un agente cambie mis cosas?</b></summary>

Gesher es cuidadoso (los cambios se verifican, los borrados masivos se guardan en `~/.config/gesher/backups`,
los recordatorios y las notas borrados van a Eliminados recientemente), pero hace lo que tu agente le pide.
Conecta solo las apps que necesites y vigila qué le dejas cambiar a un agente.
</details>

<details>
<summary><b>¿Qué necesito?</b></summary>

Un Mac con Apple silicon y macOS 26 o posterior. Gesher está probado en macOS 27; macOS 26 debería funcionar, pero aún
no se ha probado. Los Mac con Intel no son compatibles. No hace falta Xcode.
</details>

<details>
<summary><b>¿Qué no puede hacer?</b></summary>

Las notas de los contactos y algunas ediciones de Freeform (formas,
notas adhesivas, renombrar tableros) están reservadas por macOS a las propias apps de Apple. Maps es de solo
lectura. [Lista completa](../limitations.md).
</details>

<details>
<summary><b>¿Por qué el instalador me pide la contraseña?</b></summary>

Solo para crear un certificado de firma en tu Mac, de modo que las actualizaciones conserven los permisos
que diste. Si dices que no, Gesher funciona igual; solo tendrás que volver a dar acceso tras cada
actualización.
</details>

<details>
<summary><b>¿En qué se diferencia de los servidores MCP basados en AppleScript?</b></summary>

AppleScript solo ve lo que cada app decidió exponer a los scripts, necesita la app abierta y pide acceso
de Automatización. Gesher llama a los frameworks sobre los que están hechas las apps: es más rápido,
funciona con las apps cerradas y llega a lo que los scripts no alcanzan, como las secciones y listas
inteligentes de Reminders, las etiquetas y tablas de Notes, y los tableros de Freeform.
</details>

<details>
<summary><b>¿Puedo fiarme de la descarga?</b></summary>

Cada versión se compila a partir del commit etiquetado de este repositorio y se publica con un archivo `.sha256`. El
instalador verifica el SHA-256 de la descarga. Las herramientas no están notarizadas por Apple; en su
lugar, el instalador las firma en tu Mac. Las [notas de seguridad](../../SECURITY.md) explican de qué te
protegen los permisos de Gesher.
</details>

<details>
<summary><b>¿Una actualización de macOS lo romperá?</b></summary>

Podría pasar: Gesher usa partes de macOS que Apple no promete mantener estables. Si algo cambia, Gesher se
detiene con un mensaje claro en vez de improvisar, y `gesher doctor` muestra qué está afectado.
</details>

<details>
<summary><b>¿Cómo lo actualizo o lo desinstalo?</b></summary>

`gesher update` instala la última versión y conserva tus permisos y conexiones. `gesher uninstall` elimina
Gesher y lo desconecta de tus apps de IA.
</details>

<details>
<summary><b>¿Qué significa "Gesher"?</b></summary>

Es *puente* en hebreo (גשר), y se pronuncia *GUÉ-sher*.
</details>

## Cómo funciona

Cada app del Mac tiene una pequeña herramienta de línea de comandos que también es un servidor
[MCP](https://modelcontextprotocol.io). Carga el framework sobre el que está construida la propia app y lo
llama directamente, así que cada cambio sigue el mismo camino que si lo hicieras en la app. Una sola
declaración por acción se convierte en el comando del CLI, su ayuda, la herramienta MCP y su esquema, así
que nunca se desincronizan.

Más información: [arquitectura](../architecture.md) · [permisos](../permissions.md) ·
[configurar apps de IA](../clients.md) · [guía de instalación para agentes](../install.md) · [contribuir en un fork](../../AGENTS.md)

## Sobre este proyecto

Gesher es experimental y está mantenido. Los informes de errores son bienvenidos, sobre todo si una
actualización de macOS rompe algo: abre un [issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose) con tu versión de macOS, la app y la salida de
`gesher doctor`. Las pull requests son bienvenidas, pero se revisan despacio. Las preguntas e ideas van en
[Discussions](https://github.com/EphraimElgrabli/gesher/discussions). Los informes de seguridad, por el [reporte privado](../../SECURITY.md).

Si Gesher hace tu Mac un poquito más mágico, una ⭐ ayuda a que otras personas lo encuentren.

<sub>Gesher es un proyecto independiente, sin relación con Apple Inc. ni respaldado por ella. Apple, Mac,
macOS, iCloud y los nombres de las apps son marcas comerciales de Apple Inc., usadas solo para indicar con
qué apps funciona Gesher. Gesher no incluye código ni gráficos de Apple. [Notas legales](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
