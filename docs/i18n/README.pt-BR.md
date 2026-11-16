<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher: uma ponte entre os agentes de IA e os apps do seu Mac" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">Sua IA, conheça seu Mac.</h3>

<p align="center">
  O Gesher deixa o Claude, o Codex, o Cursor e qualquer outro app de IA compatível com MCP trabalharem com seus apps<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b> e <b>Freeform</b>,<br>
  de forma nativa e privada, direto no seu Mac. Sem AppleScript, sem Shortcuts, sem cliques simulados na tela.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="Versão mais recente" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple silicon" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="Funciona com qualquer cliente MCP" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="Licença: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
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
  <b>Português</b> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*Esta tradução pode estar atrás do [README em inglês](../../README.md), que é a versão de referência.*

<p align="center">
  🔒 <b>O Gesher roda inteiramente no seu Mac.</b> Sem servidores do Gesher, sem contas, sem telemetria.
</p>

> [!TIP]
> **Agentes de IA:** leiam o [`llms.txt`](../../llms.txt) para ter o mapa deste projeto, e o
> [`docs/install.md`](../install.md) para instalar o Gesher para o seu usuário.

## Comece em um minuto

**O jeito fácil: peça ao seu agente.** Cole isto no Claude Code, Codex, Cursor ou qualquer agente que
consiga rodar comandos:

```text
Instale o Gesher no meu Mac e conecte-o aos meus apps de IA seguindo
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**Ou faça você mesmo, em três passos:**

**1. Instale.** Uma linha só no Terminal. Ele encontra seus apps de IA e pergunta quais conectar.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. Diga sim ao macOS.** Numa nova janela do Terminal, rode `gesher permissions` e clique em **Permitir**.
O Notes e o Freeform precisam de uma arrastada para o Acesso Total ao Disco; o Gesher abre a janela para
você.

**3. Pergunte.** Reinicie seu app de IA e experimente *"O que tenho na agenda amanhã?"*

<p align="center">
  <b>Funciona com</b><br>
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
  <img alt="qualquer cliente MCP" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## Experimente pedir

> *"Como está a minha semana? Encontre duas horas livres para trabalho focado e bloqueie na agenda."*

> *"Transforme minha nota da **viagem a Lisboa** numa lista de malas no Reminders, para o dia antes do voo."*

> *"Vai chover na minha corrida das 18h? Se for, passe para amanhã de manhã."*

> *"Quem faz aniversário este mês? Coloque ideias de presente nas minhas notas."*

> *"Ache uma farmácia aberta agora perto da minha próxima reunião e quanto tempo leva para ir a pé."*

> *"Crie um quadro no Freeform para a reforma da cozinha com os links da minha nota **Cozinha**."*

| Sem o Gesher | Com o Gesher |
|---|---|
| *"Não tenho acesso à sua agenda, mas você pode conferir e me dizer…"* | Lê sua agenda, encontra o horário livre e reserva. ✅ |
| Você copia uma nota para o chat e depois copia a resposta de volta. | Seu agente lê a nota e edita ali mesmo, em Markdown. ✅ |
| Você pede um lembrete e o agente manda você abrir o Reminders. | *"Me lembre de comprar leite quando eu sair do escritório."* Feito, com alerta por localização. ✅ |

## O que seu agente pode fazer

| | App | Seu agente pode… | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | adicionar, concluir e organizar tarefas: listas, seções, tags, subtarefas, listas inteligentes, modelos | [28 ferramentas](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | ler sua agenda, achar tempo livre, criar e mover eventos, responder convites | [17 ferramentas](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | encontrar qualquer pessoa por nome, telefone ou e-mail, atualizar cartões, grupos, aniversários | [21 ferramentas](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | ler e escrever notas em Markdown, com checklists, tabelas, tags e anexos | [29 ferramentas](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | buscar lugares, ver horários de funcionamento, planejar rotas e tempos de viagem | [6 ferramentas](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | ver a previsão em qualquer lugar, hora a hora, e a qualidade do ar | [10 ferramentas](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | ler seus quadros, criar novos, adicionar textos, links, imagens e arquivos | [6 ferramentas](../../apps/freeform/README.md) |

Se você usa o iCloud, cada mudança chega ao seu iPhone e iPad, como se você mesmo tivesse feito.

## O que faz dele diferente

- **É nativo de verdade.** O Gesher chama os mesmos frameworks (privados) do macOS que os próprios apps
  usam. Nada de AppleScript, nada de Atalhos, nada de cliques pelas janelas, e os apps não precisam estar
  abertos (só o Freeform abre discretamente em segundo plano quando seu agente adiciona algo a um quadro).
- **É privado.** Nada para se cadastrar, nada coletado, nada para configurar na nuvem.
- **É cuidadoso.** Cada mudança é relida para confirmar que deu certo. Exclusões em massa ganham backup
  antes. Lembretes e notas apagados vão para Apagados Recentemente, e as edições de notas podem ficar
  atreladas à versão que o agente leu, para ele nunca sobrescrever uma mudança que não viu.
- **Você continua no controle.** O macOS pede sua permissão para cada app, e você pode dar a um agente
  o seu Calendar sem os seus Contacts.
- **Fala a língua dos agentes.** Nomes em vez de ids, datas como *"next tuesday 14:00"* e erros que dizem
  o que fazer em seguida, para os agentes acertarem com menos tentativas.

## Também é um CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

JSON compacto para scripts e agentes, `--format pretty` para pessoas. `<app>-cli --help` explica o resto.

## Conecte mais apps de IA depois

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

Prefere fazer na mão, ou usa algo que não está na lista? Cada app é um servidor MCP padrão
(`reminders-cli mcp`, `calendar-cli mcp`, …): [configuração para cada app de IA](../clients.md).

## Perguntas frequentes

<details>
<summary><b>Meus dados são enviados para algum lugar?</b></summary>

Não pelo Gesher. Ele roda no seu Mac e não tem servidores. O Weather e o Maps consultam os serviços da
Apple, exatamente como esses apps fazem. O que você compartilha com um agente de IA vai para o provedor
desse agente, como tudo o que você digita nele; com um modelo local no LM Studio ou no opencode, sua
conversa nunca sai do seu Mac.
</details>

<details>
<summary><b>É seguro deixar um agente mexer nas minhas coisas?</b></summary>

O Gesher é cuidadoso (as mudanças são verificadas, exclusões em massa ganham backup em
`~/.config/gesher/backups`, lembretes e notas apagados vão para Apagados Recentemente), mas ele faz o que
seu agente pede. Conecte só os apps de que você precisa e fique de olho no que deixa um agente mudar.
</details>

<details>
<summary><b>Do que eu preciso?</b></summary>

Um Mac com Apple silicon e macOS 26 ou posterior. O Gesher é testado no macOS 27; no macOS 26 ele deve funcionar, mas
ainda não foi testado. Macs Intel não são suportados. Não precisa de Xcode.
</details>

<details>
<summary><b>O que ele não consegue fazer?</b></summary>

Notas de contatos e algumas edições no Freeform (formas, notas adesivas, renomear
quadros) são reservados pelo macOS aos próprios apps da Apple. O Maps é só leitura. [Lista completa](../limitations.md).
</details>

<details>
<summary><b>Por que o instalador pede minha senha?</b></summary>

Só para criar um certificado de assinatura no seu Mac, para que as atualizações mantenham as permissões
que você deu. Se disser não, o Gesher funciona do mesmo jeito; você só vai precisar liberar o acesso de
novo depois das atualizações.
</details>

<details>
<summary><b>Qual a diferença para servidores MCP baseados em AppleScript?</b></summary>

O AppleScript só enxerga o que cada app escolheu expor para scripts, precisa do app aberto e pede acesso
de Automação. O Gesher chama os frameworks sobre os quais os apps são construídos: é mais rápido, funciona
com os apps fechados e alcança o que os scripts não alcançam, como seções e listas inteligentes do
Reminders, tags e tabelas do Notes e quadros do Freeform.
</details>

<details>
<summary><b>Posso confiar no download?</b></summary>

Cada versão é compilada a partir do commit com tag deste repositório e publicada com um arquivo `.sha256`. O
instalador verifica o SHA-256 do download. As ferramentas não são notarizadas pela Apple; em vez disso, o
instalador as assina no seu Mac. As [notas de segurança](../../SECURITY.md) explicam do que as permissões
do Gesher protegem você.
</details>

<details>
<summary><b>Uma atualização do macOS vai quebrar o Gesher?</b></summary>

Pode acontecer: o Gesher usa partes do macOS que a Apple não promete manter estáveis. Se algo mudar, o
Gesher para com uma mensagem clara em vez de chutar, e o `gesher doctor` mostra o que foi afetado.
</details>

<details>
<summary><b>Como atualizo ou removo?</b></summary>

`gesher update` instala a versão mais recente e mantém suas permissões e conexões. `gesher uninstall` remove
o Gesher e o desconecta dos seus apps de IA.
</details>

<details>
<summary><b>O que significa "Gesher"?</b></summary>

É *ponte* em hebraico (גשר), e se pronuncia *GUÉ-cher*.
</details>

## Como funciona

Cada app do Mac ganha uma pequena ferramenta de linha de comando que também é um servidor
[MCP](https://modelcontextprotocol.io). Ela carrega o framework sobre o qual o próprio app é construído e o
chama diretamente, então cada mudança segue o mesmo caminho que seguiria se você a fizesse no app. Uma única
declaração por ação vira o comando do CLI, sua ajuda, a ferramenta MCP e o seu schema, então eles nunca
ficam fora de sincronia.

Saiba mais: [arquitetura](../architecture.md) · [permissões](../permissions.md) ·
[configurar apps de IA](../clients.md) · [guia de instalação para agentes](../install.md) · [contribuir num fork](../../AGENTS.md)

## Sobre este projeto

O Gesher é experimental e mantido. Relatos de bug são bem-vindos, principalmente quando uma atualização do
macOS quebra algo: abra uma [issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose) com a sua versão do macOS, o app e a saída de `gesher doctor`.
Pull requests são bem-vindos, mas revisados devagar. Perguntas e ideias vão nas [Discussions](https://github.com/EphraimElgrabli/gesher/discussions).
Relatos de segurança, pelo [reporte privado](../../SECURITY.md).

Se o Gesher deixar seu Mac um pouquinho mais mágico, uma ⭐ ajuda outras pessoas a encontrá-lo.

<sub>O Gesher é um projeto independente, sem afiliação com a Apple Inc. nem endossado por ela. Apple, Mac,
macOS, iCloud e os nomes dos apps são marcas registradas da Apple Inc., usadas apenas para indicar com
quais apps o Gesher funciona. O Gesher não inclui nenhum código ou arte da Apple. [Notas legais](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
