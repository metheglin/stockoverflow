# DEVELOP: 指標算出拡張（EV/EBITDA・業績予想乖離率）

## 背景

`CalculateFinancialMetricsJob` が算出する指標は成長性（YoY）・収益性（ROE/ROA/マージン）・CF・連続指標・バリュエーション（PER/PBR/PSR/配当利回り）をカバーしているが、以下の指標が未算出のまま残っている。

1. **EV/EBITDA**: `FinancialMetric` の `data_json` スキーマに `ev_ebitda` が定義済みだが、算出ロジックが実装されていない
2. **業績予想乖離率（Earning Surprise）**: `FinancialValue` の `data_json` に `forecast_net_sales`, `forecast_operating_income` 等の業績予想データが格納されているが、実績との比較分析がおこなわれていない

これらの指標はスクリーニングや企業評価に広く使われるため、指標算出パイプラインに組み込む価値が高い。

## 実装内容

### 1. EV/EBITDA算出ロジック追加

`FinancialMetric` モデルにクラスメソッドを追加し、`CalculateFinancialMetricsJob` で呼び出す。

**算出ロジック:**
- EV (Enterprise Value) = 時価総額 + 有利子負債 - 現金同等物
  - 時価総額 = 株価 × 発行済株式数 (`stock_price * fv.shares_outstanding`)
  - 有利子負債: 直接データがないため、`total_assets - net_assets` で近似（簡易版）
  - 現金同等物: `fv.cash_and_equivalents`
- EBITDA = 営業利益 + 減価償却費
  - 減価償却費: XBRLから取得できない場合、営業利益をそのまま使用（簡易版、保守的に低い EV/EBITDA を返す）
  - 将来的に EDINET XBRL から減価償却費を抽出して精度向上を検討

**配置先:** `FinancialMetric.get_ev_ebitda(fv, stock_price)` → 結果は `data_json["ev_ebitda"]` に格納

### 2. 業績予想乖離率（Earning Surprise）算出

前期の業績予想と当期の実績を比較し、乖離率を算出する。

**算出ロジック:**
- 前期の `FinancialValue` の `data_json` から `forecast_net_sales`, `forecast_operating_income`, `forecast_net_income`, `forecast_eps` を取得
- 当期の `FinancialValue` の実績値と比較
- 乖離率 = (実績 - 予想) / |予想|

**格納先:** `FinancialMetric` の `data_json` に以下を追加
- `revenue_surprise`: 売上予想乖離率
- `operating_income_surprise`: 営業利益予想乖離率
- `net_income_surprise`: 純利益予想乖離率
- `eps_surprise`: EPS予想乖離率

**配置先:** `FinancialMetric.get_surprise_metrics(current_fv, previous_fv)` クラスメソッド

### 3. FinancialMetric data_json スキーマ拡張

`define_json_attributes` に以下を追加:
- `revenue_surprise: { type: :decimal }`
- `operating_income_surprise: { type: :decimal }`
- `net_income_surprise: { type: :decimal }`
- `eps_surprise: { type: :decimal }`

### 4. CalculateFinancialMetricsJob への組み込み

`calculate_metrics_for` メソッドで、既存の指標算出に加えて:
- `get_ev_ebitda` を呼び出し、結果を `data_json` にマージ
- `get_surprise_metrics` を呼び出し、結果を `data_json` にマージ

## テスト

- `FinancialMetric.get_ev_ebitda`: 正常算出、株価nil、cash_and_equivalents nil、shares_outstanding nil
- `FinancialMetric.get_surprise_metrics`: 正常算出（ポジティブ/ネガティブサプライズ）、前期予想nil、実績nil

## 成果物

- `app/models/financial_metric.rb` - `get_ev_ebitda`, `get_surprise_metrics` クラスメソッド追加 + data_jsonスキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 新指標の算出組み込み
- `spec/models/financial_metric_spec.rb` - 新メソッドのテスト追加
