# ep_files

加工データをGitHubで共有し、設計PCから公開、加工施設PCから取得するためのリポジトリです。

GitHubの仕様上、100 MiBを超える単一ファイルは通常のGitではpushできません。

## 使うボタンは2つだけ

### 設計PC・個人PC

`push.cmd` をダブルクリックします。

Inventorなどから出力した新しい `.cnc`・`.stl` を、日付フォルダへ整理してGitHubへ公開します。

```text
最新データを取得
  → 新規ファイルを整理
  → add・commit
  → もう一度最新データを確認
  → push
```

GitHubへのログインと、このリポジトリへの書き込み権限が必要です。

自動commitでは、追加した合計件数と拡張子別件数を表示し、commitメッセージにも記録します。

```text
Add 5 machining files (.cnc: 2, .stl: 3)
```

### 加工施設PC・CNC付属PC

`pull.cmd` をダブルクリックします。

GitHubから最新データを取得するだけです。加工施設PCからadd・commit・pushは行いません。

```text
GitHubの更新を確認 → 安全に適用
```

publicリポジトリの取得だけなので、通常はGitHubへのログインや書き込み権限は不要です。

## 加工データの整理形式

新しい加工データは次の形に整理されます。

```text
ep_files/
├─ CNC/
│  └─ 2025-08-14/
│     └─ part.cnc
├─ STL/
│  └─ 2025-08-14/
│     └─ model.stl
└─ others/
   └─ 2025-08-14/
      └─ unregistered-file.pdf
```

整理ルールは `tools/organize.config.json` で管理します。

```json
{
  "extensionToEquipment": {
    ".cnc": "CNC",
    ".stl": "STL",
    ".nc": "NC",
    ".dxf": "DXF"
  },
  "unregisteredEquipment": "others",
  "dateSource": "GitFirstAdded"
}
```

登録されていない拡張子と拡張子なしのファイルは、`others/YYYY-MM-DD/` へ整理して一緒にpushします。README、`push.cmd`、`pull.cmd`、`.gitignore`、`tools` 配下は管理ファイルとして対象外です。

`dateSource` は次から選べます。

- `GitFirstAdded`（初期値）: Gitへ初めて追加したコミットの日付。Git未登録ファイルはWindowsの作成日時。
- `CreationTime`: Windowsの作成日時。
- `LastWriteTime`: ファイルの最終更新日時。

同名ファイルがある場合は上書きせず、`part (2).cnc` のように連番を付けます。修正版は、できれば `part_v2.cnc` のような分かりやすい新しい名前で追加してください。

## 安全仕様

### 設計PC用

- 自動で公開するのは、設定済み拡張子の新規加工データだけです。
- 既存のGit管理ファイルに変更や削除がある場合は、勝手にcommitせず停止します。
- README、スクリプト、設定ファイル、関係のない形式は自動addしません。
- 100 MiBを超えるファイルはcommit前に停止します。
- 通信やpushに失敗しても、ローカルデータと作成済みcommitは残ります。原因を直して再実行できます。

### 加工施設PC用

- GitHub上の履歴へ安全に早送りできる場合だけ更新します。
- ローカル変更、ローカルcommit、履歴の分岐がある場合は上書きせず停止します。
- add・commit・push、加工データの整理は行いません。

## GitHubへのログイン

設計PCからpushするユーザーは、リポジトリの所有者またはCollaboratorとして登録されたGitHubアカウントでログインしてください。Git for Windowsに含まれるGit Credential Managerを使うと、初回push時にブラウザ認証が表示されます。

Gitの作成者名・メールアドレスが未設定の共用PCでは、個人情報を公開しない共用PC用の値をこのリポジトリ内だけに自動設定します。個人名で記録したい場合は、公開前に次を設定します。

```powershell
git config user.name "表示名"
git config user.email "GitHubのnoreplyメールアドレス"
```

## `.gitignore`

`.gitignore` では、`Thumbs.db`、`Desktop.ini`、`.DS_Store`、エディタのswapファイルなどを除外します。

`.tmp`、`.bak` などは加工工程で必要になる可能性があるため、一律では除外していません。

## 内部ツール

通常は `tools` フォルダを操作する必要はありません。

- `Publish-EpFiles.ps1`: 設計PC用の公開処理
- `Pull-EpFiles.ps1`: 加工施設PC用の読み取り専用更新処理
- `Organize-EpFiles.ps1`: ファイル整理処理
- `organize.config.json`: 整理ルール
