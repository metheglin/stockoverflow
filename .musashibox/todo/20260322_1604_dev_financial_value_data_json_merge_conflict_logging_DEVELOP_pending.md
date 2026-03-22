# FinancialValue data_json マージ時の競合検出・ログ出力

## 概要

`ImportJquantsFinancialDataJob#import_financial_value` および `ImportEdinetDocumentsJob#supplement_with_xbrl` では、既存の `data_json` に新しいデータを `merge` している。このとき、同一キーに対して異なる値が存在する場合（例: JQUANTS の forecast_net_sales と EDINET の forecast_net_sales が異なる）、後から処理されたソースの値で上書きされる。

現在はこの上書きが無条件に発生し、ログにも記録されない。データソース間の不整合は、計算指標の正確性に直接影響するため、マージ時の競合を検出してログに記録する仕組みが必要。

## 対象ファイル

- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/import_edinet_documents_job.rb`

## 実装内容

1. `data_json` のマージ前に、既存データと新規データの共通キーを比較するヘルパーメソッドを作成
2. 値が異なるキーがある場合、ログに以下の情報を出力:
   - company_id, fiscal_year_end, scope
   - 競合キー名、既存値、新規値、採用された値
   - データソース（EDINET / JQUANTS）
3. 競合検出のヘルパーは `FinancialValue` モデルのクラスメソッドとして定義し、テスト可能にする

## テスト

- 共通キーに同一値がある場合、競合として検出されないこと
- 共通キーに異なる値がある場合、競合情報が正しく返されること
- 片方のみにキーが存在する場合（新規追加）、競合として検出されないこと
- nil値と実値の場合の扱い（nilは競合とみなさない）

## 備考

- 将来的には競合情報をDBに保存し、データ品質レポートとして参照可能にすることも検討
- ログレベルは `warn` とし、通常運用でも視認できるようにする
