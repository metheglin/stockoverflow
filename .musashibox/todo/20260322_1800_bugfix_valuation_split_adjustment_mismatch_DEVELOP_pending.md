# DEVELOP: PER/PBR算出における株式分割調整の不整合修正

## 概要

`CalculateFinancialMetricsJob.load_stock_price` が `adjusted_close`（分割調整済み終値）を返す一方、`FinancialMetric.get_valuation_metrics` は `fv.eps` / `fv.bps`（財務諸表上の未調整値）をそのまま使用している。株式分割が発生した企業において、PER/PBR/PSRが系統的に誤った値となる。

## 問題の詳細

### 現在のコード

```ruby
# CalculateFinancialMetricsJob#load_stock_price (app/jobs/calculate_financial_metrics_job.rb:110-116)
# adjusted_close を返す（分割調整済み）
def load_stock_price(fv)
  DailyQuote
    .where(company_id: fv.company_id)
    .where(traded_on: (fv.fiscal_year_end - 7.days)..(fv.fiscal_year_end + 7.days))
    .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
    .pick(:adjusted_close)
end

# FinancialMetric.get_valuation_metrics (app/models/financial_metric.rb:110-128)
# stock_price(=adjusted_close) と 未調整EPS/BPS を直接比較
result["per"] = safe_divide(stock_price, fv.eps)  # 分割調整済み価格 / 未調整EPS
result["pbr"] = safe_divide(stock_price, fv.bps)  # 分割調整済み価格 / 未調整BPS
```

### 具体例

- 企業X: 2025年3月決算 EPS = 1,000円、株価 = 5,000円 → PER = 5.0（正しい）
- 2025年7月に1:10の株式分割を実施
- `adjusted_close` は分割遡及調整により 500円 に変更される
- 再計算時: PER = 500 / 1,000 = 0.5（**実態のPER 5.0と大幅に乖離**）

### 影響範囲

- PER, PBR, PSR, EV/EBITDA の全バリュエーション指標
- スクリーニングにおけるバリュエーション基準のフィルタ結果
- 過去に遡って分割調整されるため、歴史的なバリュエーション推移も不正確

## 修正方針

以下のいずれかのアプローチで修正する:

### 案A: 未調整株価を使用する

`load_stock_price` で `close_price`（未調整終値）を使う。財務諸表のEPS/BPSは未調整なので、未調整同士の比較で正しいPER/PBRが得られる。

```ruby
def load_stock_price(fv)
  DailyQuote
    .where(company_id: fv.company_id)
    .where(traded_on: (fv.fiscal_year_end - 7.days)..(fv.fiscal_year_end + 7.days))
    .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
    .pick(:close_price)  # adjusted_close → close_price
end
```

- 利点: 最もシンプル。財務諸表の値と同時点の株価を使うため正確
- 欠点: `close_price` が nil の可能性（JQUANTSデータの品質に依存）

### 案B: EPS/BPSを分割調整する

`adjustment_factor` を取得し、EPS/BPSを調整してから `adjusted_close` と比較する。

```ruby
def load_stock_price_with_factor(fv)
  DailyQuote
    .where(company_id: fv.company_id)
    .where(traded_on: (fv.fiscal_year_end - 7.days)..(fv.fiscal_year_end + 7.days))
    .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
    .pick(:adjusted_close, :adjustment_factor)
end

# get_valuation_metrics で adjustment_factor を用いて EPS/BPS を調整
adjusted_eps = fv.eps / adjustment_factor
result["per"] = safe_divide(adjusted_close, adjusted_eps)
```

- 利点: 全株価が分割調整済みの一貫した基準になる
- 欠点: adjustment_factor が nil の可能性、ロジックが複雑

### 推奨: 案A

シンプルさを優先し、未調整株価と未調整EPS/BPSの比較とする。決算日時点の株価で算出するバリュエーション指標の意味としても、案Aが適切。

## テスト

- `FinancialMetric.get_valuation_metrics` の既存テストは変更不要（引数として株価を受ける設計のため）
- `CalculateFinancialMetricsJob` の `load_stock_price` 返却値の変更を確認（`close_price` を返すこと）
- 分割調整が発生した場合でも、PERが妥当な範囲に収まることを確認するテストケースの追加を検討

## 関連TODO

- `20260322_1603_dev_daily_quote_adjusted_price_methods` - DailyQuoteに調整済み価格メソッドを追加するTODO。本修正と方向性を合わせる必要がある
