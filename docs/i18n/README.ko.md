<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher: AI 에이전트와 Mac 앱을 잇는 다리" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">당신의 AI, 이제 당신의 Mac과 만나세요.</h3>

<p align="center">
  Gesher와 함께라면 Claude, Codex, Cursor를 비롯해 MCP를 지원하는 모든 AI 앱이<br>
  <b>Reminders, Calendar, Contacts, Notes, Maps, Weather</b>, 그리고 <b>Freeform</b>을 다룰 수 있어요.<br>
  네이티브로, 프라이빗하게, 바로 당신의 Mac 안에서. AppleScript도, Shortcuts도, 화면 클릭 자동화도 필요 없어요.
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="최신 릴리스" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple 실리콘" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="모든 MCP 클라이언트 지원" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="라이선스: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <b>한국어</b> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*이 번역은 [영어 README](../../README.md)보다 뒤처질 수 있으며, 영어판이 기준입니다.*

<p align="center">
  🔒 <b>Gesher 자체는 전부 당신의 Mac 안에서 실행됩니다.</b> Gesher 서버도, 계정도, 텔레메트리도 없습니다.
</p>

> [!TIP]
> **AI 에이전트라면:** 프로젝트 전체 지도는 [`llms.txt`](../../llms.txt)를, 사용자를 위해 Gesher를 설치하는 방법은
> [`docs/install.md`](../install.md)를 읽어 주세요.

## 1분이면 시작

**가장 쉬운 방법: 에이전트에게 맡기세요.** Claude Code, Codex, Cursor 등 명령을 실행할 수 있는 에이전트에
이렇게 붙여 넣기만 하면 됩니다:

```text
다음 안내에 따라 내 Mac에 Gesher를 설치하고 내 AI 앱들과 연결해 줘:
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**직접 하고 싶다면, 세 단계면 돼요:**

**1. 설치하기.** Terminal에 한 줄이면 충분해요. AI 앱을 찾아 어떤 앱을 연결할지 물어봅니다.

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. macOS에 '허용' 누르기.** 새 Terminal 창에서 `gesher permissions`를 실행하고 **허용**을 클릭하세요.
Notes와 Freeform은 '전체 디스크 접근 권한'으로 한 번 끌어다 놓기만 하면 되고, 그 창은 Gesher가 열어 줘요.

**3. 물어보기.** AI 앱을 다시 시작하고 *"내일 일정이 뭐야?"* 라고 물어보세요.

<p align="center">
  <b>지원하는 앱</b><br>
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
  <img alt="모든 MCP 클라이언트" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## 이렇게 물어보세요

> *"이번 주 일정 어때? 집중해서 일할 빈 시간 두 시간 찾아서 잡아 줘."*

> *"**리스본 여행** 메모를 Reminders 짐 싸기 목록으로 만들어 줘. 마감은 비행기 타기 전날로."*

> *"저녁 6시 달리기할 때 비 와? 오면 내일 아침으로 옮겨 줘."*

> *"이번 달에 생일인 사람 누구야? 선물 아이디어를 메모에 추가해 줘."*

> *"다음 미팅 장소 근처에 지금 문 연 약국 찾아 주고, 걸어서 얼마나 걸리는지도 알려 줘."*

> *"**주방** 메모에 있는 링크로 주방 리모델링용 Freeform 보드를 만들어 줘."*

| Gesher 없이 | Gesher와 함께 |
|---|---|
| *"캘린더에 접근할 수 없지만, 직접 확인하고 알려 주시면…"* | 일정을 읽고, 빈 시간을 찾아, 바로 잡아 둡니다. ✅ |
| 메모를 채팅에 복사하고, 답을 다시 복사해 붙여 넣기. | 에이전트가 메모를 읽고 Markdown으로 바로 수정합니다. ✅ |
| 미리 알림을 부탁하면, 에이전트는 Reminders를 열어 보라고만 하죠. | *"사무실 나갈 때 우유 사라고 알려 줘."* 위치 기반 알림까지 완료. ✅ |

## 에이전트가 할 수 있는 일

| | 앱 | 에이전트가 할 수 있는 일 | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | 할 일 추가, 완료, 정리: 목록, 섹션, 태그, 하위 작업, 스마트 목록, 템플릿 | [도구 28개](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | 일정 확인, 빈 시간 찾기, 이벤트 생성과 이동, 초대 응답 | [도구 17개](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | 이름, 전화번호, 이메일로 누구든 찾기, 연락처 카드, 그룹, 생일 업데이트 | [도구 21개](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | Markdown으로 메모 읽고 쓰기, 체크리스트, 표, 태그, 첨부 파일까지 | [도구 29개](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | 장소 검색, 영업시간 확인, 경로와 이동 시간 계획 | [도구 6개](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | 어디서든 시간별 일기 예보와 대기질 확인 | [도구 10개](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | 보드 읽기와 새로 만들기, 텍스트, 링크, 이미지, 파일 추가 | [도구 6개](../../apps/freeform/README.md) |

iCloud를 쓰고 있다면 모든 변경 사항이 iPhone과 iPad에도 그대로 반영됩니다. 마치 직접 바꾼 것처럼요.

## 무엇이 다른가요

- **진짜 네이티브.** Gesher는 앱들이 직접 쓰는 것과 똑같은 (비공개) macOS 프레임워크를 호출합니다. AppleScript도,
  Shortcuts도, 창을 이리저리 클릭하는 것도 없고, 앱을 열어 둘 필요도 없어요 (에이전트가 보드에 무언가를 추가할 때만
  Freeform이 백그라운드에서 조용히 열립니다).
- **프라이빗.** 가입할 것도, 수집되는 것도, 클라우드에서 설정할 것도 없어요.
- **신중함.** 변경할 때마다 다시 읽어서 제대로 됐는지 확인합니다. 일괄 삭제 전에는 먼저 백업하고요. 삭제된 미리 알림과
  메모는 '최근 삭제된 항목'으로 가며, 메모 편집은 에이전트가 읽은 버전에 묶어 둘 수 있어서 에이전트가 보지 못한 변경
  사항을 덮어쓰는 일이 없습니다.
- **주도권은 당신에게.** macOS가 앱마다 따로 권한을 묻기 때문에, Contacts는 빼고 Calendar만 에이전트에게 맡길 수도
  있어요.
- **에이전트의 언어를 압니다.** ID 대신 이름으로, 날짜는 *"next tuesday 14:00"*처럼, 오류 메시지는 다음에 무엇을
  해야 할지 알려 주니까 에이전트가 더 적은 시도로 제대로 해냅니다.

## CLI로도 쓸 수 있어요

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

스크립트와 에이전트에게는 간결한 JSON을, 사람에게는 `--format pretty`를. 나머지는 `<app>-cli --help`가 알려 줍니다.

## 나중에 AI 앱 더 연결하기

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

직접 설정하고 싶거나 목록에 없는 앱을 쓰고 있나요? 모든 앱은 표준 MCP 서버입니다
(`reminders-cli mcp`, `calendar-cli mcp`, …): [AI 앱별 설정 방법](../clients.md).

## 자주 묻는 질문

<details>
<summary><b>내 데이터가 어딘가로 전송되나요?</b></summary>

Gesher는 보내지 않습니다. Mac에서 실행되고 서버도 없어요. Weather와 Maps는 해당 앱들과 똑같이 Apple 서비스에
요청합니다. AI 에이전트와 공유한 내용은, 거기에 입력하는 다른 모든 것과 마찬가지로 그 에이전트의 제공업체로 전달됩니다.
LM Studio나 opencode에서 로컬 모델을 쓰면 대화가 Mac 밖으로 나가지 않아요.
</details>

<details>
<summary><b>에이전트가 내 데이터를 바꾸게 둬도 안전한가요?</b></summary>

Gesher는 신중합니다(변경 사항을 검증하고, 일괄 삭제는 `~/.config/gesher/backups`에 백업하며, 삭제된 미리 알림과
메모는 '최근 삭제된 항목'으로 갑니다). 하지만 결국 에이전트가 요청한 대로 실행합니다. 필요한 앱만 연결하고, 에이전트에게
무엇을 바꾸게 하는지 잘 지켜봐 주세요.
</details>

<details>
<summary><b>무엇이 필요한가요?</b></summary>

Apple 실리콘이 탑재되고 macOS 26 이상이 설치된 Mac. Gesher는 macOS 27에서 테스트되었고, macOS 26에서도 동작할 것으로 보이지만
아직 테스트하지 않았습니다. Intel Mac은 지원하지 않아요. Xcode는 필요 없습니다.
</details>

<details>
<summary><b>할 수 없는 일은요?</b></summary>

연락처 메모와 일부 Freeform 편집(도형, 스티커 메모, 보드 이름 변경)은 macOS가 Apple의 자체
앱에만 허용합니다. Maps는 읽기 전용이에요. [전체 목록](../limitations.md).
</details>

<details>
<summary><b>설치 프로그램이 왜 암호를 묻나요?</b></summary>

Mac에 서명 인증서를 만들기 위해서일 뿐이에요. 덕분에 업데이트 후에도 허용해 둔 권한이 그대로 유지됩니다.
거절해도 Gesher는 잘 작동하고, 업데이트할 때마다 권한을 다시 허용하면 돼요.
</details>

<details>
<summary><b>AppleScript 기반 MCP 서버와는 뭐가 다른가요?</b></summary>

AppleScript는 각 앱이 스크립트에 공개해 둔 부분만 볼 수 있고, 앱이 열려 있어야 하며, '자동화' 권한도
요청합니다. Gesher는 앱이 기반으로 삼는 프레임워크를 직접 호출해요. 그래서 더 빠르고, 앱이 닫혀 있어도
작동하며, Reminders의 섹션과 스마트 목록, Notes의 태그와 표, Freeform 보드처럼 스크립트로는 닿지 않는
부분까지 다룰 수 있어요.
</details>

<details>
<summary><b>다운로드한 파일을 믿어도 되나요?</b></summary>

모든 릴리스는 이 저장소의 태그된 커밋에서 빌드되며 `.sha256` 파일과 함께 공개됩니다. 설치 프로그램은 다운로드한 파일의 SHA-256을 검사합니다. 도구들은
Apple의 공증을 받지 않은 대신, 설치 프로그램이 당신의 Mac에서 직접 서명합니다. Gesher의 권한이 무엇을 막아 주는지는
[보안 안내](../../SECURITY.md)에서 설명합니다.
</details>

<details>
<summary><b>macOS 업데이트로 고장 나지 않을까요?</b></summary>

그럴 수 있습니다. Gesher는 Apple이 안정성을 약속하지 않은 macOS의 일부를 사용하거든요. 무언가 바뀌면 Gesher는
추측하지 않고 명확한 메시지와 함께 멈추며, `gesher doctor`로 무엇이 영향을 받는지 확인할 수 있습니다.
</details>

<details>
<summary><b>업데이트하거나 삭제하려면요?</b></summary>

`gesher update`는 최신 버전을 설치하면서 권한과 연결은 그대로 유지합니다. `gesher uninstall`은 Gesher를 제거하고
AI 앱과의 연결도 해제합니다.
</details>

<details>
<summary><b>"Gesher"는 무슨 뜻인가요?</b></summary>

히브리어로 *다리*(גשר)라는 뜻이고, *GEH-sher*('게셰르'에 가까운 소리)라고 발음합니다.
</details>

## 작동 방식

Mac의 각 앱마다 작은 명령줄 도구가 있고, 이 도구는 동시에 [MCP](https://modelcontextprotocol.io) 서버이기도
합니다. 앱 자체가 기반으로 하는 프레임워크를 불러와 직접 호출하기 때문에, 모든 변경은 앱에서 직접 할 때와 똑같은 경로를
거칩니다. 동작 하나당 선언 하나가 CLI 명령, 도움말, MCP 도구와 그 스키마가 되므로 서로 어긋날 일이 없어요.

더 읽어 보기: [아키텍처](../architecture.md) · [권한](../permissions.md) ·
[AI 앱 설정](../clients.md) · [에이전트 설치 가이드](../install.md) · [포크에서 기여하기](../../AGENTS.md)

## 이 프로젝트에 대해

Gesher는 개인 프로젝트로, 있는 그대로 공유됩니다. 실험적이며 지원은 제공하지 않습니다. 작게 유지하기 위해 issue와
pull request는 닫혀 있어요. 대신 언제든 포크해서 당신만의 것으로 만들어 보세요. 보안 관련 제보는
[비공개 제보](../../SECURITY.md)로 환영합니다.

Gesher 덕분에 당신의 Mac이 조금 더 마법 같아졌다면, ⭐ 하나가 다른 사람들이 이 프로젝트를 찾는 데 큰 도움이 됩니다.

<sub>Gesher는 독립 프로젝트로, Apple Inc.와 제휴하거나 Apple Inc.의 보증을 받지 않았습니다. Apple, Mac, macOS,
iCloud 및 각 앱 이름은 Apple Inc.의 상표이며, Gesher가 어떤 앱과 함께 동작하는지 설명하기 위해서만 사용됩니다.
Gesher에는 Apple의 코드나 아트워크가 포함되어 있지 않습니다. [법적 고지](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
