# DEVELOP: 時価総額ティア分類・ティア移行検出

## 概要

企業を時価総額ベースでティア（マイクロ・小型・中型・大型・超大型）に分類し、ティア間の移行（昇格・降格）を検出・記録する。サイズベースのスクリーニングとティア移行のシグナル検出を可能にする。

## 背景・動機

既存システムではCompanyモデルに `market_code`（プライム・スタンダード・グロース）の市場区分があるが、これは東証の制度的な分類であり、実質的な企業規模を反映しない。

時価総額ティアは投資分析において以下の理由で重要:
- **機関投資家の投資対象制約**: 一定以上の時価総額がないと機関投資家が投資できない。ティア昇格は需給改善のシグナル
- **サイズファクター分析**: 小型株効果など、企業規模と株価リターンの関係分析
- **成長軌跡の可視化**: 小型→中型→大型へと成長する企業の特定はプロジェクト目標「飛躍の前兆検出」に直結
- **ピアグループの精緻化**: 同じ業種でも時価総額が10倍異なる企業を比較することの不適切性を回避

### 既存TODOとの差別化

- `dev_daily_valuation_timeseries`: 日次のPER/PBR/時価総額を保持するテーブル・ジョブの設計。時価総額の算出はここで行われるが、**ティア分類や移行検出は含まれない**
- `dev_metric_percentile_ranking`: 指標の相対順位であり、絶対的なサイズ分類ではない

## 実装内容

### 1. ティア定義（定数）

```ruby
# Company に定義
MARKET_CAP_TIERS = {
  micro: { max: 10_000_000_000 },              # 100億円未満
  small: { min: 10_000_000_000, max: 50_000_000_000 },  # 100-500億円
  mid: { min: 50_000_000_000, max: 300_000_000_000 },   # 500-3000億円
  large: { min: 300_000_000_000, max: 1_000_000_000_000 }, # 3000億-1兆円
  mega: { min: 1_000_000_000_000 },             # 1兆円以上
}.freeze
```

### 2. Company にクラスメソッドを追加

```ruby
# 時価総額からティアを判定する
#
# @param market_cap [Numeric, nil] 時価総額（円）
# @return [Symbol, nil] :micro, :small, :mid, :large, :mega or nil
#
# 例:
#   Company.get_market_cap_tier(45_000_000_000)  # => :small
#   Company.get_market_cap_tier(500_000_000_000) # => :large
#
def self.get_market_cap_tier(market_cap)

# 当期と前期のティアを比較し、移行情報を返す
#
# @param current_cap [Numeric, nil] 当期末時価総額
# @param previous_cap [Numeric, nil] 前期末時価総額
# @return [Hash, nil] ティア移行情報
#
# 例:
#   Company.get_tier_migration(80_000_000_000, 40_000_000_000)
#   # => { from: :small, to: :mid, direction: :upgrade, cap_growth: 1.0 }
#
def self.get_tier_migration(current_cap, previous_cap)
```

### 3. FinancialMetric の data_json 拡張

```ruby
market_cap_tier: { type: :string },         # "micro"|"small"|"mid"|"large"|"mega"
market_cap_at_fiscal_end: { type: :integer }, # 決算期末時点の時価総額
tier_migration_direction: { type: :string },  # "upgrade"|"downgrade"|nil
tier_migration_from: { type: :string },       # 前期のティア
```

### 4. CalculateFinancialMetricsJob への組み込み

- 既存の `load_stock_price(fv)` で取得した決算期末株価と `shares_outstanding` から時価総額を算出
- `Company.get_market_cap_tier()` でティアを判定
- 前期のFinancialMetricからティア比較を実施
- 結果を data_json にマージ

### 5. スクリーニングでの活用

```ruby
# Company::ScreeningQuery のフィルタ拡張例

# ティア指定スクリーニング
# { market_cap_tier: "small" }  -- 小型株のみ

# ティア昇格企業のスクリーニング
# { tier_migration_direction: "upgrade" } -- 直近期でティア昇格した企業
```

## テスト

### Company.get_market_cap_tier

- 各ティアの境界値テスト（100億円未満=micro, 100億円=small, 500億円=mid, 3000億円=large, 1兆円=mega）
- nilの場合にnilを返すこと
- 負値やゼロの場合にmicroを返すこと

### Company.get_tier_migration

- 昇格ケース: small→mid のとき direction=:upgrade
- 降格ケース: large→mid のとき direction=:downgrade
- 変化なしケース: 同一ティアのとき nil
- 前期データなしのケース: nil

## 依存関係

- DailyQuote（株価）と FinancialValue（shares_outstanding）のデータが存在すること
- `dev_daily_valuation_timeseries` で時価総額が永続化されれば、そこからの参照も可能
- 独立して実装可能（DailyQuoteから直接株価を参照する方式でも実現可能）
