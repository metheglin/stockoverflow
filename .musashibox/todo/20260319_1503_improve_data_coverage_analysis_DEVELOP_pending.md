# データカバレッジ分析ツールの実装

## 概要

各企業のデータ充足状況（何年分のデータがあるか、どのフィールドが欠損しているか）を可視化・レポートするツールを実装する。信頼性の高い分析のためにはデータの完全性を把握することが不可欠。

## 背景

DataIntegrityCheckJobは連続増収増益の整合性やsyncの鮮度をチェックしているが、「そもそも何年分のデータがあるのか」「特定のフィールドがどの程度埋まっているか」といったカバレッジの観点が不足している。6期連続増収増益のスクリーニングで、実際にはデータが3年分しかないために結果が信頼できないケースを検出できない。

## 実装内容

### 1. Companyモデルへのメソッド追加

- `get_data_coverage_summary` → そのCompanyの財務データカバレッジを返す
  - financial_valuesのレコード数（scope/period_type別）
  - 最古/最新の fiscal_year_end
  - financial_metricsのレコード数
  - daily_quotesの最古/最新の traded_on、レコード数
  - 主要フィールドの充足率（net_sales, operating_income, operating_cf等がnilでないレコードの割合）

### 2. データカバレッジ集計rakeタスク

`lib/tasks/data_coverage.rake` に以下を実装:

- `rake data:coverage:summary` → 全企業のカバレッジサマリーを標準出力に表示
  - 年数別の企業数分布（1年分: N社、2年分: N社、...、10年以上: N社）
  - フィールド別の全体充足率
- `rake data:coverage:detail[securities_code]` → 特定企業の詳細カバレッジ
- `rake data:coverage:gaps` → データギャップ（抜けている年度がある企業）のリスト

### 3. ApplicationPropertyへの集計結果保存

- kind: `data_coverage` として集計結果をdata_jsonに保存
- 集計日時を記録し、前回との差分を確認可能にする

### 4. テスト

- Companyモデルの`get_data_coverage_summary`メソッドのテスト（DBアクセスが必要なため最小限のレコードで）
