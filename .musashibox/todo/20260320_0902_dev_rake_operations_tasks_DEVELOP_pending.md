# TODO: 日常運用のためのRakeタスク群の整備

## 概要

各インポート・計算・チェックジョブの実行インターフェースをRakeタスクとして整備し、日常運用の効率を向上させる。

## 背景・課題

現在、全てのデータ操作は `rails console` 経由でジョブクラスを直接呼び出す必要がある:

```ruby
SyncCompaniesJob.perform_now(api_key: "xxx")
ImportDailyQuotesJob.perform_now(full: true)
```

この方式には以下の問題がある:
- 操作ミスのリスク（引数名のtypo等）
- cron連携が煩雑（`rails runner` を使う必要がある）
- データ確認のためにconsoleを開く手間
- 新しい開発者がどのジョブをどのように実行するか把握しにくい

## 実装方針

### lib/tasks/sync.rake - データ同期タスク

```
rake sync:companies                         # 企業マスタ同期
rake sync:daily_quotes                      # 日次株価（増分）
rake sync:daily_quotes[full]                # 日次株価（全件）
rake sync:financial_data                    # JQUANTS財務データ（増分）
rake sync:financial_data[full]              # JQUANTS財務データ（全件）
rake sync:edinet                            # EDINET書類（増分）
rake sync:edinet[from_date,to_date]         # EDINET書類（期間指定）
```

### lib/tasks/metrics.rake - 指標計算タスク

```
rake metrics:calculate                      # 指標計算（差分）
rake metrics:recalculate                    # 指標計算（全件再計算）
rake metrics:recalculate[company_id]        # 特定企業の指標再計算
```

### lib/tasks/check.rake - データチェックタスク

```
rake check:integrity                        # データ整合性チェック
rake check:status                           # 同期ステータス表示
```

### lib/tasks/data.rake - データ確認タスク

```
rake data:summary                           # 全テーブルのレコード数サマリ
rake data:company[code]                     # 特定企業の概要表示
```

### 設計方針

- 各Rakeタスクは対応するJobの `perform_now` を呼び出すシンプルなラッパー
- API Keyは `Rails.application.credentials` から取得（Rakeタスクの引数にはしない）
- 実行開始・終了のログ出力を統一フォーマットで出す
- 引数バリデーションを最低限実施し、不正な引数には分かりやすいエラーメッセージを返す

## テスト

- Rakeタスクはジョブのラッパーのため、テスト不要（ジョブ側でテスト済み）
- data:summary, data:company, check:status のような読み取り専用タスクについても、出力フォーマットの検証は不要

## 依存関係

- 既存の全ジョブに依存
- dev_job_scheduling と補完的な関係（スケジュール実行 vs 手動実行）
