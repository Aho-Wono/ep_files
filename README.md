# ep_files

自由に編集xしてください。GitHubの仕様上、100MBを超える単一ファイルはアップロードできません。

## 加工データの自動整理

リポジトリ内の加工データを、`加工機材/日付/ファイル` の形に一括整理できます。

例:

```text
ep_files/
└─ CNC/
   └─ 2025-08-14/
      ├─ part.cnc
      └─ model.stl
```

### ダブルクリックで使う

- `tools/preview-organize.cmd`: 移動内容だけを表示します。初回はこちらで確認してください。
- `organize.cmd`: 実際にフォルダを作成してファイルを移動します。

同名ファイルが移動先にある場合は上書きせず、`part (2).cnc` のように連番を付けます。すでに正しい場所にあるファイルは移動しないため、何度実行しても構いません。

### ターミナルから使う

PowerShellでリポジトリのルートに移動して実行します。

```powershell
# プレビュー（ファイルを移動しない）
.\tools\Organize-EpFiles.ps1 -WhatIf

# 実行
.\tools\Organize-EpFiles.ps1
```

PowerShellの実行ポリシーで止められるPCでは、次のコマンドを使えます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Organize-EpFiles.ps1
```

### 整理ルールを変更する

`tools/organize.config.json` の `extensionToEquipment` に「拡張子: 加工機材フォルダ」を記載します。

```json
{
  "extensionToEquipment": {
    ".cnc": "CNC",
    ".stl": "STL"
  },
  "dateSource": "GitFirstAdded"
}
```

`dateSource` は次から選べます。

- `GitFirstAdded`（初期値）: Gitへ初めて追加したコミットの日付。まだGit管理されていないファイルはWindowsの作成日時。
- `CreationTime`: Windowsの作成日時。
- `LastWriteTime`: ファイルの最終更新日時。

GitでcloneしたファイルのWindows作成日時はcloneした日に変わるため、通常は `GitFirstAdded` が最も安定します。
