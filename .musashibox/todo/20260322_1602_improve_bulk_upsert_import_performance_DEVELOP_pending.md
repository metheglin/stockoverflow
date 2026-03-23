# Import Job のバルクupsert最適化

## 概要

現在のインポートジョブ（ImportDailyQuotesJob, ImportJquantsFinancialDataJob, SyncCompaniesJob）は、レコードごとに `find_or_initialize_by` + `save` を実行している。上場企業約4000社、日次株価データを数年分取り込む場合、各レコードに対してSELECT + INSERT/UPDATE が個別に発行され、非常に低速となる。

Rails 6以降で利用可能な `upsert_all` を活用し、バルクでのINSERT/UPDATEに切り替えることで大幅なパフォーマンス改善が見込まれる。

## 対象ファイル

- `app/jobs/import_daily_quotes_job.rb`
- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/sync_companies_job.rb`

## 実装内容

### ImportDailyQuotesJob
- `import_quotes` メソッドで、レコード配列を一括で `DailyQuote.upsert_all` に渡すよう変更
- unique_by: `[:company_id, :traded_on]` を指定
- バッチサイズ（例: 1000件ずつ）で分割して処理

### ImportJquantsFinancialDataJob
- `import_statement` のバルク化は data_json のマージロジックが複雑なため、限定的に適用
- 同一日付の一括取得結果をまとめて処理する方式を検討

### SyncCompaniesJob
- company属性の一括upsertに切り替え
- unique_by: `[:securities_code]` を指定

## 注意事項

- `upsert_all` は callbacks（before_save, after_save）を発火しないため、影響範囲を確認
- data_json のマージが必要なケースでは upsert_all の適用が困難。個別更新のままとするか、マージロジックをSQL側で実現するか判断が必要
- SQLite の UPSERT（ON CONFLICT ... DO UPDATE）サポート状況を確認
