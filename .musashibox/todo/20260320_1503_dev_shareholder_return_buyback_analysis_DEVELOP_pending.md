# DEVELOP: 株主還元・自社株買い分析メトリクスの実装

## 概要

TSR（株主総利回り）、自社株買い利回り、総還元性向を算出し、企業の株主還元姿勢を定量的に評価する。既存の配当分析TODO（`dev_dividend_payout_analysis`）を補完し、自社株買いを含む総合的な株主還元分析を実現する。

## 背景

`dev_dividend_payout_analysis` は配当性向・増配率・連続増配期数を扱うが、近年の日本企業は自社株買いを積極化しており、配当だけでは株主還元の全体像が把握できない。FinancialValueには `treasury_shares`（自己株式数）と `shares_outstanding`（発行済株式数）が格納されており、DailyQuotesには株価データがあるため、以下の指標を算出可能。

- **TSR（Total Shareholder Return）**: 株価上昇+配当を含む「投資家の実際のリターン」
- **自社株買い利回り**: 自社株買いによる1株当たり価値の向上度
- **総還元性向**: 配当+自社株買い / 純利益 → 利益をどれだけ株主に還元しているか

## 実装内容

### 1. FinancialMetric にメソッド追加

```ruby
# 株主還元指標を算出する
#
# @param fv [FinancialValue] 当期の財務数値
# @param previous_fv [FinancialValue, nil] 前期の財務数値
# @param current_price [Numeric, nil] 当期末の株価
# @param previous_price [Numeric, nil] 前期末の株価
# @return [Hash] 株主還元指標のHash（data_json格納用）
#
# 例:
#   result = FinancialMetric.get_shareholder_return_metrics(fv, prev_fv, 2500, 2000)
#   # => {
#   #   "tsr" => 0.28,                  # TSR 28%（株価上昇25% + 配当利回り3%）
#   #   "buyback_yield" => 0.02,        # 自社株買い利回り 2%
#   #   "total_payout_ratio" => 0.55,   # 総還元性向 55%
#   #   "treasury_share_ratio" => 0.05, # 自己株式比率 5%
#   #   "shares_change_rate" => -0.02,  # 発行済株式数変化率 -2%（自社株買い効果）
#   # }
def self.get_shareholder_return_metrics(fv, previous_fv, current_price, previous_price)
```

### 2. 各指標の算出ロジック

#### TSR（株主総利回り）

```
TSR = (当期末株価 - 前期末株価 + 1株当たり配当) / 前期末株価
```

- `current_price`, `previous_price` は CalculateFinancialMetricsJob で DailyQuote から取得
- `dividend_per_share_annual` は `fv.data_json` に格納済み

#### buyback_yield（自社株買い利回り）

```
buyback_yield = (前期自己株式数 - 当期自己株式数) / 当期発行済株式数
```

- 自己株式が増加 = 自社株買い実施 → プラスの利回り
- 注: treasury_shares の増減で把握。ストックオプション行使等による減少もあり得るが、大勢としては自社株買い

ただし、treasury_shares が「株式数」で格納されているか「金額」で格納されているかはデータソースにより異なる可能性がある。JQUANTSの `TrShFY` は株式数（千株単位）。

#### total_payout_ratio（総還元性向）

```
total_payout_ratio = (配当総額 + 自社株買い金額) / 純利益
```

- 配当総額: `fv.data_json["total_dividend_paid"]` がある場合はそれを使用、ない場合は `dividend_per_share_annual * shares_outstanding` で近似
- 自社株買い金額: `(前期treasury_shares - 当期treasury_shares) * 平均株価` で近似（正確な金額はCFから取得が理想だが、現在のXBRLパーサーでは未取得）
- 代替案: 発行済株式数の変化率から推定する簡易版を提供

#### treasury_share_ratio（自己株式比率）

```
treasury_share_ratio = 自己株式数 / (発行済株式数 + 自己株式数)
```

#### shares_change_rate（発行済株式数変化率）

```
shares_change_rate = (当期発行済株式数 - 前期発行済株式数) / 前期発行済株式数
```

- マイナス = 自社株買いにより1株当たり価値が向上

### 3. data_json スキーマ拡張

```ruby
tsr: { type: :decimal },
buyback_yield: { type: :decimal },
total_payout_ratio: { type: :decimal },
treasury_share_ratio: { type: :decimal },
shares_change_rate: { type: :decimal },
```

### 4. CalculateFinancialMetricsJob への組み込み

- 既存の `load_stock_price(fv)` を活用して当期末株価を取得
- 前期末株価の取得ロジックを追加（前期の fiscal_year_end ± 7日の DailyQuote）
- `get_shareholder_return_metrics` を呼び出して data_json にマージ

## テスト

### FinancialMetric

- `.get_shareholder_return_metrics`:
  - 正常系: TSR, buyback_yield, total_payout_ratio が正しく算出されること
  - 自社株買い未実施（treasury_shares 変化なし）の場合に buyback_yield = 0 となること
  - 配当なしの場合にTSRが株価上昇分のみとなること
  - 前期データなしの場合にTSR, buyback_yield, shares_change_rate がnilとなること
  - 赤字企業の場合に total_payout_ratio がnilまたは負値として処理されること

## 成果物

- `app/models/financial_metric.rb` - `get_shareholder_return_metrics` メソッド追加 + data_json スキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 前期末株価取得の追加 + 新指標の算出組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加

## 依存関係

- `dev_dividend_payout_analysis` とは独立して実装可能（配当分析は配当固有の指標、本TODOは自社株買いを含む総合還元分析）
- DailyQuoteの前期末株価を参照するため、DailyQuoteデータがある程度蓄積されていることが望ましい
