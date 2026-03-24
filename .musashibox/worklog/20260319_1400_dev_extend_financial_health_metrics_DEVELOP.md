# WORKLOG: 財務健全性・効率性指標の追加

作業日時: 2026-03-24

## 作業概要

FinancialMetric に財務健全性（流動比率・負債資本倍率・ネット負債資本倍率）と効率性（総資産回転率・売上総利益率・販管費率）の6指標を追加した。

## 作業内容

### 1. FinancialMetric data_json スキーマ拡張

`define_json_attributes :data_json` に以下6フィールドを追加:
- `current_ratio` (流動比率)
- `debt_to_equity` (負債資本倍率)
- `net_debt_to_equity` (ネット負債資本倍率)
- `asset_turnover` (総資産回転率)
- `gross_margin` (売上総利益率)
- `sga_ratio` (販管費率)

### 2. 算出メソッド追加

- `FinancialMetric.get_financial_health_metrics(fv)` - 財務健全性3指標を算出
  - FinancialValue の data_json 内 XBRL データ（current_assets, current_liabilities, noncurrent_liabilities, shareholders_equity）を活用
  - 各指標で必要なデータがnilや分母が0の場合は該当指標をスキップ
- `FinancialMetric.get_efficiency_metrics(fv)` - 効率性3指標を算出
  - gross_profit, sga_expenses は FinancialValue の data_json から取得
  - net_sales, total_assets は固定カラムから取得

### 3. CalculateFinancialMetricsJob 組み込み

`calculate_metrics_for` メソッド内で上記2メソッドを呼び出し、結果を `json_updates` にマージするよう修正。

### 4. SectorMetric DATA_JSON_METRICS 追加

新6指標をセクター統計集計対象に追加。CalculateSectorMetricsJob による再集計時にセクター別統計に反映される。

### 5. テスト

`spec/models/financial_metric_spec.rb` に以下のテストを追加:
- `.get_financial_health_metrics`: 正常値算出、各値nil時スキップ、分母0スキップ、全nil時空Hash (5 examples)
- `.get_efficiency_metrics`: 正常値算出、gross_profit nil時スキップ、net_sales 0時スキップ、total_assets nil時スキップ、全nil時空Hash (5 examples)

全114モデルテスト通過を確認。

## 変更ファイル

- `app/models/financial_metric.rb` - スキーマ拡張 + 2メソッド追加
- `app/jobs/calculate_financial_metrics_job.rb` - 新メソッド呼び出し追加
- `app/models/sector_metric.rb` - DATA_JSON_METRICS に6指標追加
- `spec/models/financial_metric_spec.rb` - テスト10件追加
