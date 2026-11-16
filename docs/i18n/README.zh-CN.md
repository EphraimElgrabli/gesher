<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher：连接 AI 智能体与 Mac 应用的桥梁" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">让你的 AI，认识你的 Mac。</h3>

<p align="center">
  有了 Gesher，Claude、Codex、Cursor 以及任何支持 MCP 的 AI 应用都能直接使用你的<br>
  <b>Reminders、Calendar、Contacts、Notes、Maps、Weather</b> 和 <b>Freeform</b>，<br>
  原生、私密，一切都在你自己的 Mac 上完成。无需 AppleScript，无需 Shortcuts，也不用模拟点击屏幕。
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple 芯片" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="适用于任何 MCP 客户端" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="许可证：GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <b>简体中文</b> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*此译文可能落后于[英文 README](../../README.md)，以英文版为准。*

<p align="center">
  🔒 <b>Gesher 本身完全运行在你的 Mac 上。</b>没有 Gesher 服务器，无需注册账户，也不收集任何遥测数据。
</p>

> [!TIP]
> **AI 智能体请注意：** 阅读 [`llms.txt`](../../llms.txt) 了解本项目的全貌，再按照
> [`docs/install.md`](../install.md) 为你的用户安装 Gesher。

## 一分钟上手

**最省心的方式：交给你的智能体。** 把下面这段话粘贴到 Claude Code、Codex、Cursor 或任何能执行命令的智能体里：

```text
请按照以下说明，在我的 Mac 上安装 Gesher 并把它连接到我的 AI 应用：
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**或者亲自动手，只需三步：**

**1. 安装。** 在 Terminal 里运行一行命令。它会找出你的 AI 应用，并询问要连接哪些。

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. 对 macOS 说“好”。** 打开一个新的 Terminal 窗口，运行 `gesher permissions`，然后点按 **允许**。Notes
和 Freeform 还需要拖一下到“完全磁盘访问权限”里，Gesher 会帮你打开对应的窗口。

**3. 开口问。** 重启你的 AI 应用，试试问它 *“我明天有什么安排？”*

<p align="center">
  <b>支持的应用</b><br>
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
  <img alt="任何 MCP 客户端" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## 试着这样问

> *“我这周安排得怎么样？帮我找出两个小时的空档用来专注工作，并把时间锁定。”*

> *“把我的 **里斯本之旅** 备忘录变成 Reminders 里的行李清单，截止时间设在出发前一天。”*

> *“我晚上 6 点跑步的时候会下雨吗？如果会，就改到明天早上。”*

> *“这个月有谁过生日？把礼物点子记到我的备忘录里。”*

> *“在我下一个会议地点附近找一家现在还开着的药店，看看走过去要多久。”*

> *“用我 **厨房** 备忘录里的链接，为厨房翻新做一块 Freeform 白板。”*

| 没有 Gesher | 有了 Gesher |
|---|---|
| *“我无法访问你的日历，不过你可以自己看一下再告诉我……”* | 读取你的日程，找到空档，直接订好。✅ |
| 你把备忘录复制进聊天框，再把回答复制回去。 | 智能体直接读取备忘录，并以 Markdown 原地编辑。✅ |
| 你想设个提醒，智能体却让你自己去打开 Reminders。 | *“我离开办公室时提醒我买牛奶。”* 搞定，还附带位置提醒。✅ |

## 你的智能体能做什么

| | 应用 | 你的智能体可以… | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | 添加、完成和整理任务：列表、分组、标签、子任务、智能列表、模板 | [28 个工具](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | 查看日程、寻找空闲时间、创建和移动日程、回复邀请 | [17 个工具](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | 按姓名、电话或邮箱找到任何人，更新名片、群组和生日 | [21 个工具](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | 以 Markdown 读写备忘录，支持清单、表格、标签和附件 | [29 个工具](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | 搜索地点、查看营业时间、规划路线和路程时间 | [6 个工具](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | 查看任何地方的逐小时天气预报，以及空气质量 | [10 个工具](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | 读取你的白板、创建新白板，添加文字、链接、图片和文件 | [6 个工具](../../apps/freeform/README.md) |

如果你在用 iCloud，所有改动都会同步到你的 iPhone 和 iPad，就像你亲手改的一样。

## 与众不同之处

- **真正的原生。** Gesher 调用的正是这些应用自己使用的（私有）macOS 框架。不用 AppleScript，不用
  Shortcuts，不用模拟点击窗口，也不必打开应用（只有在智能体往白板上添加内容时，Freeform 才会在后台悄悄打开）。
- **注重隐私。** 无需注册，不收集任何数据，也没有什么要在云端配置。
- **小心谨慎。** 每次改动后都会回读确认是否成功。批量删除前会先备份。删除的提醒事项和备忘录会进入
  “最近删除”；编辑备忘录时还可以绑定智能体读取时的版本，绝不会覆盖它没看到过的改动。
- **一切由你掌控。** macOS 会为每个应用单独征求你的许可，你可以只把 Calendar 交给智能体，而不给
  Contacts。
- **懂智能体的语言。** 用名称而不是 ID，日期可以写成 *"next tuesday 14:00"*，报错信息会告诉它下一步
  该怎么做，让智能体少走弯路、一次做对。

## 它也是一套 CLI

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

默认输出紧凑的 JSON，方便脚本和智能体使用；加上 `--format pretty` 则是给人看的版本。其余用法请看 `<app>-cli --help`。

## 稍后连接更多 AI 应用

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

想手动配置，或者你用的应用不在列表里？每个应用都是标准的 MCP 服务器
（`reminders-cli mcp`、`calendar-cli mcp`……）：[各 AI 应用的配置方法](../clients.md)。

## 常见问题

<details>
<summary><b>我的数据会被发送到别处吗？</b></summary>

Gesher 不会。它运行在你的 Mac 上，没有任何服务器。Weather 和 Maps 会像这两个应用本身一样向 Apple 的服务查询。
你与 AI 智能体分享的内容会发送给该智能体的提供方，就像你在里面输入的其他内容一样；如果在 LM Studio 或
opencode 中使用本地模型，你的对话就始终不会离开你的 Mac。
</details>

<details>
<summary><b>让智能体修改我的东西安全吗？</b></summary>

Gesher 很谨慎（改动会被验证，批量删除会先备份到 `~/.config/gesher/backups`，删除的提醒事项和备忘录会进入
“最近删除”），但它终究会照智能体的要求去做。只连接你需要的应用，并留意你允许智能体修改了什么。
</details>

<details>
<summary><b>需要什么条件？</b></summary>

一台搭载 Apple 芯片、运行 macOS 26 或更高版本的 Mac。Gesher 已在 macOS 27 上测试；在 macOS 26 上应该可以运行，但尚未测试。
不支持 Intel Mac。不需要 Xcode。
</details>

<details>
<summary><b>有什么做不到的？</b></summary>

联系人备注以及部分 Freeform 编辑（形状、便签、重命名白板）被 macOS 保留给 Apple
自家应用使用。Maps 为只读。[完整列表](../limitations.md)。
</details>

<details>
<summary><b>安装程序为什么要我输入密码？</b></summary>

只是为了在你的 Mac 上创建一个签名证书，这样更新后你已授予的权限都会保留。不输入也没关系，Gesher
照样能用，只是每次更新后需要重新授权。
</details>

<details>
<summary><b>它和基于 AppleScript 的 MCP 服务器有什么不同？</b></summary>

AppleScript 只能看到每个应用愿意开放给脚本的部分，需要应用保持打开，还要申请“自动化”权限。Gesher
直接调用这些应用本身所依赖的框架：应用关着也能用，还能做到脚本做不到的事，比如 Reminders
的分组和智能列表、Notes 的标签和表格，以及 Freeform 白板。
</details>

<details>
<summary><b>下载的文件可信吗？</b></summary>

每个版本都从本仓库打了标签的提交构建，并附带 `.sha256` 文件发布。安装程序会校验下载文件的 SHA-256。这些工具没有经过 Apple 公证，而是由安装程序在你的
Mac 上完成签名。[安全说明](../../SECURITY.md)介绍了 Gesher 的权限能防范哪些风险。
</details>

<details>
<summary><b>macOS 更新会让它失效吗？</b></summary>

有可能：Gesher 用到了 Apple 没有承诺保持稳定的 macOS 组件。一旦有变化，Gesher 会停下来并给出清晰的提示，而不是
瞎猜；`gesher doctor` 会告诉你哪些功能受到了影响。
</details>

<details>
<summary><b>如何更新或卸载？</b></summary>

`gesher update` 会安装最新版本，并保留你的权限和连接。`gesher uninstall` 会移除 Gesher，并断开它与你的 AI 应用的连接。
</details>

<details>
<summary><b>“Gesher”是什么意思？</b></summary>

它是希伯来语的“*桥*”（גשר），读作 *GEH-sher*（发音近似“盖舍尔”）。
</details>

## 工作原理

每个 Mac 应用都配有一个小巧的命令行工具，它同时也是一个 [MCP](https://modelcontextprotocol.io)
服务器。它加载应用本身所基于的框架并直接调用，因此每一次改动都和你在应用里亲手操作走的是同一条路径。每个操作只需一份声明，
就能同时生成 CLI 命令、帮助文本、MCP 工具及其 schema，让它们始终保持一致。

延伸阅读：[架构](../architecture.md) · [权限](../permissions.md) ·
[AI 应用配置](../clients.md) · [智能体安装指南](../install.md) · [在 fork 中参与开发](../../AGENTS.md)

## 关于本项目

Gesher 仍处于实验阶段，但会持续维护。欢迎报告 bug，尤其是 macOS 更新导致的故障：请附上 macOS 版本、应用和
`gesher doctor` 的输出，提交 [issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose)。也欢迎 pull request，但审核会比较慢。问题和想法请发到
[Discussions](https://github.com/EphraimElgrabli/gesher/discussions)。安全问题请通过[私密报告](../../SECURITY.md)提交。

如果 Gesher 让你的 Mac 多了一点魔法，点个 ⭐ 就能帮更多人发现它。

<sub>Gesher 是一个独立项目，与 Apple Inc. 无关，也未获其认可。Apple、Mac、macOS、iCloud 及各应用名称均为
Apple Inc. 的商标，此处仅用于说明 Gesher 支持哪些应用。Gesher 不包含任何 Apple 的代码或美术素材。[法律声明](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
