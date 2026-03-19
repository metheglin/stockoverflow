# Project Management

本プロジェクトでは、AIがおこなう作業をTODOとよぶ。  
TODOは `.musashibox/todo/*.md` ファイルで表現され、これをTODOファイルとよぶ。

## TODOファイル

TODOファイルは次の命名ルールで作成される。

`{YYYYmmdd}_{HHMM}_{TODO_TITLE}_{TODO_TYPE}_{TODO_STATUS}.md`

Ex: `20260303_1202_bugfix_apiclient_pending.md`

- TODO_TITLE
  - TODOのかんたんなタイトル。英数字アンダースコア
  - 開発の種別に応じて dev,improve,bugfix などのprefixを付与する
- TODO_STATUS
  - 次のいずれかの値をとる: `pending`|`inprogress`|`done`|`completed`
  - TODO_STATUS=pending のものは、人間のレビュアーによるレビュー対象となり、レビューが完了するとステータスが `inprogress` に変更される
  - TODO_STATUS=inprogress のものは、AIによる作業・実装の対象となる
- TODO_TYPE
  - 次のいずれかの値をとる: `THINK`|`PLAN`|`DEVELOP`

## TODO_TYPE

大別して3種類のTODO_TYPEがあり、どの種類のTODOをおこなうかはプロンプトの指示にしたがうこと。  

- TODO_TYPE=THINK
  - プロンプトの具体的な指示はなく、仕様などを確認しつつ、プロジェクトを前進させるために何を計画・実装・修正すべきか考え、新たなTODOファイルを作成するタスク
- TODO_TYPE=PLAN
  - TODOファイルにしたがって、詳細仕様を示した新たなTODOファイルを作成するタスク
- TODO_TYPE=DEVELOP
  - TODOファイルにしたがって、コードの開発・実装・テスト・修正をおこなうタスク

### TODO_TYPE=THINK 作業内容

実装は一切おこなわない。詳細仕様も作成しない。本プロジェクトに必要となる開発計画・または実装・修正・テストを自ら考え、その指示を記載したTODOを作成する。

作業内容
- 成果物は新たなTODOで、 `.musashibox/todo/` 以下にタスクを作成する
  - 開発計画が必要な場合は、ファイル名の変数部分を次のように設定: TODO_TYPE=PLAN, TODO_STATUS=pending 
  - 実装・テスト・修正が必要な場合は、ファイル名の変数部分を次のように設定: TODO_TYPE=DEVELOP, TODO_STATUS=pending 
- `worklog/` 以下に作業ログを記述する
- 成果物とともにpushする

### TODO_TYPE=PLAN 作業内容

開発計画の作成

プロンプトで示された指示書(TODOファイル)に沿って開発計画をおこなう。実装は一切おこなわない。

作業内容
- 指示されたTODOファイルを確認する
- 指示にしたがって詳細仕様を作成する
- 成果物は新たな開発計画・詳細仕様書で、 `.musashibox/todo/` 以下に計画書を作成する
- プロンプトで示されたTODOファイルのTODO_STATUSを`done`に変更する
- `worklog/` 以下に作業ログを記述する
- 成果物とともにpushする

### TODO_TYPE=DEVELOP 作業内容

開発計画に基づいた実装

プロンプトで指示された計画書・指示書(TODOファイル)に沿って実装をおこなう。

作業内容
- 指示された TODOファイルを確認する
- 計画にしたがって実装をおこなう
- 実装完了したら、そのTODO_STATUSを`done`に変更する
- `worklog/` 以下に作業ログを記述する
- やり残したことがあれば、次回作業内容をTODOファイルとして作成しておく。このとき TODO_STATUS=`inprogress` で作成し、レビューをスキップしてよい
- 開発成果物とともにpushする

## WORKLOG

AIが作業をおこなう際は必ずWORKLOGとして考えたこと、開発したことなど作業ログとして記載してタスクを終えること。  
WORKLOGは次のよう名前で、作業ごとに1つのログファイルを作成すること。

`.musashibox/worklog/{YYYYmmdd}_{HHMM}_{TODO_TITLE}.md`
