# DEVELOP: PEGレシオ・成長性調整バリュエーション指標の実装

## 概要

PER/PBR/PSRなどの既存バリュエーション指標に成長率を組み合わせた「成長性調整バリュエーション指標」を算出し、成長率を考慮した割安度評価を可能にする。

## 背景

現在の `FinancialMetric.data_json` にはPER, PBR, PSR, EV/EBITDAが格納されているが、これらは静的なバリュエーション指標であり、企業の成長率を考慮しない。例えばPER 30倍の企業が「割高」かどうかは、その企業の利益成長率に大きく依存する。

成長性調整バリュエーションは以下のユースケースに直結する:

- **成長率対比で割安な企業の発見**: PER自体は高いが、成長率も高いため実質的に割安（低PEG）な企業をスクリーニング
- **GARP（Growth at a Reasonable Price）投資戦略**: 成長性と割安度のバランスがとれた企業群を抽出
- **セクター内相対比較**: 同一セクターでPERが高い企業と低い企業を、成長率を加味して再評価

## 実装内容

### 1. FinancialMetric にメソッド追加

```ruby
# 成長性調整バリュエーション指標を算出する
#
# @param metric [FinancialMetric] 算出済みメトリクス（PER/PBR/成長率が格納済み）
# @return [Hash] 成長調整バリュエーション指標のHash（data_json格納用）
#
# 例:
#   result = FinancialMetric.get_growth_adjusted_valuation(metric)
#   # => {
#   #   "peg_ratio" => 1.2,              # PEG = PER / EPS成長率(%)
#   #   "peg_ratio_revenue" => 0.8,      # 売上高成長率ベースPEG
#   #   "ev_ebitda_to_growth" => 0.6,    # EV/EBITDA / 営業利益成長率(%)
#   #   "pbr_roe_ratio" => 1.5,          # PBR / ROE (%) - ROEに対する市場評価の妥当性
#   #   "growth_value_gap" => 0.15,      # 実績成長率とPERが示唆する成長率の差
#   # }
def self.get_growth_adjusted_valuation(metric)
```

### 2. 各指標の算出ロジック

#### PEG Ratio（PER / EPS成長率）

```
PEG = PER / (eps_yoy * 100)
```

- PEGが1未満: 成長率対比で割安
- PEGが1〜2: 適正〜やや割高
- PEGが2超: 成長率対比で割高
- eps_yoyがマイナスまたはnilの場合はnilを返す（減益企業にPEGは意味をなさない）
- PERがマイナスの場合（赤字）もnilを返す

#### PEG Ratio（売上高成長率ベース）

```
PEG_revenue = PER / (revenue_yoy * 100)
```

- 赤字またはEPS変動が大きい成長企業でも売上高成長率ベースで割安度を評価できる
- SaaS企業など売上高成長が最重要視される業態に有用

#### EV/EBITDA to Growth

```
EV/EBITDA to Growth = EV/EBITDA / (operating_income_yoy * 100)
```

- EV/EBITDAを成長率で調整。低いほど割安。

#### PBR/ROE Ratio

```
PBR/ROE Ratio = PBR / (ROE * 100)
```

- ROEに対して市場がどれだけのプレミアムをつけているかを示す
- ROEが高いのにPBRが低い企業（= 低PBR/ROE比率）は市場から過小評価されている可能性

#### growth_value_gap（成長率-バリュエーション乖離）

```
implied_growth = 益利回り(1/PER) - リスクフリーレート近似(0.01)
actual_growth = eps_yoy
growth_value_gap = actual_growth - implied_growth
```

- プラス: 実際の成長が市場の織り込みより高い（潜在的に割安）
- マイナス: 実際の成長が市場期待を下回っている

### 3. data_json スキーマ拡張

```ruby
peg_ratio: { type: :decimal },
peg_ratio_revenue: { type: :decimal },
ev_ebitda_to_growth: { type: :decimal },
pbr_roe_ratio: { type: :decimal },
growth_value_gap: { type: :decimal },
```

### 4. CalculateFinancialMetricsJob への組み込み

- 既存のバリュエーション指標・成長指標・収益性指標の算出完了後に `get_growth_adjusted_valuation` を呼び出す
- 入力は算出済みの FinancialMetric 自体（PER, eps_yoy, ROE等が格納済みの状態）

## テスト

### FinancialMetric

- `.get_growth_adjusted_valuation`:
  - 正常系: PER=20, eps_yoy=0.20 の場合に peg_ratio=1.0 となること
  - eps_yoyがマイナスの場合にpeg_ratioがnilとなること
  - PERがマイナス（赤字）の場合にpeg_ratioがnilとなること
  - eps_yoy=0の場合にpeg_ratioがnilとなること（ゼロ除算回避）
  - ROE=0の場合にpbr_roe_ratioがnilとなること
  - 全ての入力指標がnilの場合に空Hashが返ること
  - growth_value_gapが正しい符号で算出されること

## 成果物

- `app/models/financial_metric.rb` - `get_growth_adjusted_valuation` メソッド追加 + data_json スキーマ拡張
- `app/jobs/calculate_financial_metrics_job.rb` - 新指標の算出組み込み
- `spec/models/financial_metric_spec.rb` - テスト追加

## 依存関係

- 既存のバリュエーション指標（PER, PBR, EV/EBITDA）と成長指標（YoY）が算出済みであること
- `dev_cagr_multiyear_growth_metrics` 完了後にはCAGRベースのPEGも追加を検討可能
