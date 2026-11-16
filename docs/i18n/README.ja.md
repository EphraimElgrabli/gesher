<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../assets/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="../assets/banner-light.png">
    <img alt="Gesher：AI エージェントと Mac のアプリをつなぐ橋" src="../assets/banner-light.png" width="100%">
  </picture>
</p>

<h3 align="center">あなたの AI に、あなたの Mac を。</h3>

<p align="center">
  Gesher を使えば、Claude、Codex、Cursor をはじめ MCP に対応したあらゆる AI アプリが<br>
  <b>Reminders、Calendar、Contacts、Notes、Maps、Weather</b>、そして <b>Freeform</b> を扱えるように。<br>
  ネイティブに、プライベートに、すべてあなたの Mac の中で。AppleScript も Shortcuts も、画面クリックの自動操作も要りません。
</p>

<p align="center">
  <a href="https://github.com/EphraimElgrabli/gesher/releases/latest"><img alt="最新リリース" src="https://img.shields.io/github/v/release/EphraimElgrabli/gesher?style=flat-square&color=FFB13D&label=release"></a>
  <img alt="macOS · Apple シリコン" src="https://img.shields.io/badge/macOS-Apple_silicon-111?style=flat-square">
  <img alt="あらゆる MCP クライアントに対応" src="https://img.shields.io/badge/MCP-any_client-6E56CF?style=flat-square">
  <a href="../../LICENSE"><img alt="ライセンス：GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-3B82F6?style=flat-square"></a>
</p>

<p align="center">
  <sub>
  <a href="../../README.md">English</a> ·
  <a href="README.he.md">עברית</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <b>日本語</b> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português</a> ·
  <a href="README.ru.md">Русский</a>
  </sub>
</p>

*この翻訳は[英語版 README](../../README.md)より古い場合があります。英語版が正式な内容です。*

<p align="center">
  🔒 <b>Gesher 自体は、すべてあなたの Mac の中で動きます。</b>Gesher のサーバーも、アカウントも、テレメトリもありません。
</p>

> [!TIP]
> **AI エージェントの方へ：** プロジェクトの全体像は [`llms.txt`](../../llms.txt) を、
> ユーザーのために Gesher をセットアップする手順は [`docs/install.md`](../install.md) をお読みください。

## 1 分ではじめよう

**いちばん簡単なのは、エージェントにお任せすること。** Claude Code、Codex、Cursor など、コマンドを実行できるエージェントに
これを貼り付けるだけです：

```text
次の手順に従って、私の Mac に Gesher をインストールし、私の AI アプリに接続してください：
https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/docs/install.md
```

**自分でやるなら、3 ステップで：**

**1. インストール。** Terminal でこの 1 行を。AI アプリを見つけて、どれを接続するか尋ねてくれます。

```sh
curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
```

**2. macOS に「OK」を。** 新しい Terminal ウインドウで `gesher permissions` を実行し、**許可** をクリック。Notes と
Freeform は「フルディスクアクセス」へ一度ドラッグするだけ。そのウインドウは Gesher が開いてくれます。

**3. 頼んでみる。** AI アプリを再起動して、*「明日の予定は？」* と聞いてみてください。

<p align="center">
  <b>対応アプリ</b><br>
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
  <img alt="あらゆる MCP クライアント" src="https://img.shields.io/badge/+_any_MCP_client-6E56CF?style=flat-square">
</p>

## こんなふうに頼んでみて

> *「今週の予定はどんな感じ？集中作業に使える 2 時間の空きを見つけて、押さえておいて。」*

> *「**リスボン旅行** のメモを Reminders の持ち物リストにして。期限はフライトの前日で。」*

> *「夕方 6 時のランニング中に雨は降りそう？降るなら明日の朝に移動して。」*

> *「今月誕生日の人は誰？プレゼントのアイデアをメモに追加しておいて。」*

> *「次の打ち合わせ場所の近くで、今開いている薬局を探して。歩いて何分かかるかも教えて。」*

> *「**キッチン** のメモにあるリンクを使って、キッチンリフォーム用の Freeform ボードを作って。」*

| Gesher なし | Gesher あり |
|---|---|
| *「カレンダーにはアクセスできないので、ご自身で確認して教えていただけますか…」* | 予定を読み、空き時間を見つけて、そのまま押さえます。✅ |
| メモをチャットにコピーして、答えをまたコピーし直す。 | エージェントがメモを読み、Markdown でその場で編集します。✅ |
| リマインダーを頼んでも、Reminders を開くよう言われるだけ。 | *「オフィスを出るときに牛乳を買うよう知らせて。」* 位置情報アラート付きで完了。✅ |

## エージェントにできること

| | アプリ | エージェントができること | |
|:-:|---|---|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/reminders-dark.png"><img src="../assets/apps/reminders-light.png" width="28" alt=""></picture> | **Reminders** | タスクの追加・完了・整理：リスト、セクション、タグ、サブタスク、スマートリスト、テンプレート | [28 ツール](../../apps/reminders/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/calendar-dark.png"><img src="../assets/apps/calendar-light.png" width="28" alt=""></picture> | **Calendar** | 予定の確認、空き時間探し、イベントの作成と移動、招待への返信 | [17 ツール](../../apps/calendar/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/contacts-dark.png"><img src="../assets/apps/contacts-light.png" width="28" alt=""></picture> | **Contacts** | 名前・電話番号・メールで誰でも検索、連絡先カード・グループ・誕生日の更新 | [21 ツール](../../apps/contacts/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/notes-dark.png"><img src="../assets/apps/notes-light.png" width="28" alt=""></picture> | **Notes** | Markdown でメモを読み書き。チェックリスト、表、タグ、添付ファイルにも対応 | [29 ツール](../../apps/notes/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/maps-dark.png"><img src="../assets/apps/maps-light.png" width="28" alt=""></picture> | **Maps** | 場所の検索、営業時間の確認、経路と所要時間の計画 | [6 ツール](../../apps/maps/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/weather-dark.png"><img src="../assets/apps/weather-light.png" width="28" alt=""></picture> | **Weather** | どこでも 1 時間ごとの天気予報と大気質をチェック | [10 ツール](../../apps/weather/README.md) |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/apps/freeform-dark.png"><img src="../assets/apps/freeform-light.png" width="28" alt=""></picture> | **Freeform** | ボードの読み取りと新規作成、テキスト・リンク・画像・ファイルの追加 | [6 ツール](../../apps/freeform/README.md) |

iCloud を使っていれば、すべての変更は iPhone や iPad にも届きます。まるで自分の手で変更したかのように。

## Gesher のここが違う

- **本当にネイティブ。** Gesher は、アプリ自身が使っているのと同じ（非公開の）macOS フレームワークを呼び出します。
  AppleScript も Shortcuts も、ウインドウをクリックして回る操作も不要。アプリを開いておく必要もありません（エージェントが
  ボードに何かを追加するときだけ、Freeform がバックグラウンドでそっと開きます）。
- **プライベート。** 登録は不要、何も収集せず、クラウドで設定することもありません。
- **慎重。** 変更のたびに読み戻して、うまくいったか確認します。一括削除の前には必ずバックアップ。削除したリマインダーや
  メモは「最近削除した項目」へ。メモの編集はエージェントが読んだバージョンにひも付けられるので、見ていない変更を
  上書きすることはありません。
- **主導権はあなたに。** macOS がアプリごとに許可を求めるので、Contacts は渡さずに Calendar だけをエージェントに
  任せる、といったことも可能です。
- **エージェントの言葉が話せる。** ID ではなく名前で、日付は *"next tuesday 14:00"* のように書けて、エラーは次に
  何をすべきかを教えてくれる。だからエージェントは少ない試行で正しくこなせます。

## CLI としても使えます

```sh
calendar-cli agenda tomorrow
reminders-cli task create 'Call the bank' --due 'friday 9:00'
notes-cli note get 'Packing list' --content markdown
maps-cli nearby pharmacy --near 'Union Square, San Francisco'
```

スクリプトやエージェント向けにはコンパクトな JSON を、人向けには `--format pretty` を。あとは `<app>-cli --help` が教えてくれます。

## あとから AI アプリを追加する

```sh
gesher connect            # finds your AI apps and asks which to connect
gesher connect --list     # what's connected where
```

手動で設定したい、あるいは一覧にないアプリを使っている？ どのアプリも標準の MCP サーバーです
（`reminders-cli mcp`、`calendar-cli mcp`、…）：[各 AI アプリの設定方法](../clients.md)。

## よくある質問

<details>
<summary><b>データはどこかに送られますか？</b></summary>

Gesher からは送られません。Gesher は Mac 上で動き、サーバーを持ちません。Weather と Maps は、それぞれのアプリと
まったく同じように Apple のサービスに問い合わせます。AI エージェントに共有した内容は、そこに入力する他のものと同様に
そのエージェントの提供元へ送られます。LM Studio や opencode でローカルモデルを使えば、会話が Mac の外に出ることはありません。
</details>

<details>
<summary><b>エージェントに自分のデータを変更させても大丈夫？</b></summary>

Gesher は慎重です（変更は検証され、一括削除は `~/.config/gesher/backups` にバックアップされ、削除したリマインダーや
メモは「最近削除した項目」に入ります）。それでも、エージェントに頼まれたことは実行します。必要なアプリだけを接続し、
エージェントに何を変更させているかには目を配っておきましょう。
</details>

<details>
<summary><b>必要なものは？</b></summary>

Apple シリコン搭載で、macOS 26 以降の Mac。Gesher は macOS 27 でテストされています。macOS 26 でも動くはずですが、
まだテストしていません。Intel Mac には対応していません。Xcode は不要です。
</details>

<details>
<summary><b>できないことは？</b></summary>

連絡先のメモと Freeform の一部の編集（図形、付箋、ボード名の変更）は、macOS が Apple
純正アプリ専用にしています。Maps は読み取り専用です。[一覧はこちら](../limitations.md)。
</details>

<details>
<summary><b>インストーラーがパスワードを求めるのはなぜ？</b></summary>

Mac 上に署名用の証明書を作成するためだけです。これで、アップデート後も許可した権限がそのまま引き継がれます。
断っても Gesher は使えます。その場合は、アップデートのたびにアクセスを許可し直すことになります。
</details>

<details>
<summary><b>AppleScript ベースの MCP サーバーとは何が違うの？</b></summary>

AppleScript で見えるのは、各アプリがスクリプトに公開している部分だけ。アプリを開いておく必要があり、
「オートメーション」の許可も求められます。Gesher はアプリ自体が土台にしているフレームワークを呼び出すので、
より速く、アプリを閉じたままでも動き、Reminders のセクションやスマートリスト、Notes のタグや表、Freeform の
ボードなど、スクリプトでは届かないところまで扱えます。
</details>

<details>
<summary><b>ダウンロードしたものは信頼できますか？</b></summary>

すべてのリリースはこのリポジトリのタグ付きコミットからビルドされ、`.sha256` ファイル付きで公開されます。インストーラーはダウンロードしたファイルの SHA-256 を確認します。
ツールは Apple の公証を受けていない代わりに、インストーラーがあなたの Mac 上で署名します。Gesher の権限が何から守ってくれるのかは
[セキュリティについて](../../SECURITY.md)で説明しています。
</details>

<details>
<summary><b>macOS のアップデートで動かなくなりませんか？</b></summary>

その可能性はあります。Gesher は、Apple が安定性を約束していない macOS の部分を使っているからです。何かが変わった場合、
Gesher は推測で動かず、わかりやすいメッセージとともに停止します。影響範囲は `gesher doctor` で確認できます。
</details>

<details>
<summary><b>アップデートやアンインストールの方法は？</b></summary>

`gesher update` で最新版をインストールでき、権限と接続はそのまま残ります。`gesher uninstall` は Gesher を削除し、
AI アプリとの接続も解除します。
</details>

<details>
<summary><b>「Gesher」ってどういう意味？</b></summary>

ヘブライ語で「*橋*」（גשר）のこと。発音は *GEH-sher*（「ゲシェル」に近い音）です。
</details>

## しくみ

Mac の各アプリには小さなコマンドラインツールが用意されていて、それぞれが [MCP](https://modelcontextprotocol.io)
サーバーでもあります。アプリ自体の土台となっているフレームワークを読み込んで直接呼び出すので、すべての変更はアプリで
自分が操作したときと同じ経路をたどります。アクションごとに 1 つの宣言から、CLI コマンド、ヘルプ、MCP ツールとそのスキーマが
生成されるので、それらが食い違うことはありません。

詳しくは：[アーキテクチャ](../architecture.md) · [権限](../permissions.md) ·
[AI アプリの設定](../clients.md) · [エージェント向けインストールガイド](../install.md) · [フォークでの開発](../../AGENTS.md)

## このプロジェクトについて

Gesher は実験的ですが、メンテナンスされています。バグ報告は歓迎します。特に macOS のアップデートで動かなくなったときは、
macOS のバージョン、アプリ、`gesher doctor` の出力を添えて [issue](https://github.com/EphraimElgrabli/gesher/issues/new/choose) を作成してください。pull request も歓迎しますが、
レビューには時間がかかります。質問やアイデアは [Discussions](https://github.com/EphraimElgrabli/gesher/discussions) へ。セキュリティに関する報告は
[非公開の報告](../../SECURITY.md)からお願いします。

Gesher であなたの Mac がちょっと魔法みたいになったら、⭐ をひとつ。ほかの人が見つけやすくなります。

<sub>Gesher は独立したプロジェクトであり、Apple Inc. とは提携しておらず、承認も受けていません。Apple、Mac、macOS、
iCloud および各アプリ名は Apple Inc. の商標で、Gesher が対応するアプリを示すためだけに使用しています。Gesher には
Apple のコードやアートワークは一切含まれていません。[法的事項](../legal.md) ·
[GPL-3.0](../../LICENSE) © Ephraim Elgrabli</sub>
