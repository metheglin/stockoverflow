# DEVELOP: 財務指標の履歴ボラティリティ・安定性スコアリング

## 概要

主要財務指標（ROE、営業利益率、売上成長率等）の過去3〜5年間の標準偏差・変動係数（CV）を算出し、企業の財務的安定性を定量化する。FinancialMetricの `data_json` に格納する。

## 背景・動機

既存のメトリクスは「単一期間の値」（当期のROE、当期のYoY等）または「連続性」（consecutive growth count）を追跡するが、指標の「ばらつき」を定量化する仕組みがない。

例えば同じ「ROE 12%」の2社でも:
- 企業A: ROE推移 8% → 14% → 6% → 18% → 12% (CV高: 不安定)
- 企業B: ROE推移 11% → 13% → 12% → 11% → 12% (CV低: 安定)

投資判断上、企業Bの方がはるかに予測可能性が高く、バリュエーションプレミアムに値する。

### 既存TODOとの差別化

- `dev_metric_consistency_reliability_score`: データの欠損・論理矛盾などデータ品質の観点
- `dev_metric_trend_classification`: 改善/悪化/横ばいの方向性分類
- **本TODO**: 指標値そのもののばらつき度合い（ビジネスの安定性・予測可能性）

プロジェクト目標との関連:
- 連続増収増益企業のスクリーニングにおいて「安定的に増収増益を続けている企業」と「たまたま6期連続しただけで振れ幅が大きい企業」を区別可能に
- 飛躍前兆の検出において、ボラティリティの低下（業績が安定し始めた）は重要なシグナル

## 実装内容

### 1. FinancialMetric にクラスメソッドを追加

```ruby
# 過去N期間の指標値のボラティリティを算出する
#
# @param metrics [Array<FinancialMetric>] 時系列順のFinancialMetric配列（古い順）
# @param window [Integer] 計算対象期数（デフォルト: 5）
# @return [Hash] ボラティリティ指標のHash（data_json格納用）
#
# 例:
#   metrics = company.financial_metrics.consolidated.annual.order(:fiscal_year_end).last(5)
#   result = FinancialMetric.get_volatility_metrics(metrics)
#   # => {
#   #   "roe_volatility" => 0.0312,           # ROEの標準偏差
#   #   "roe_cv" => 0.26,                     # ROEの変動係数
#   #   "operating_margin_volatility" => 0.018, # 営業利益率の標準偏差
#   #   "operating_margin_cv" => 0.15,
#   #   "revenue_yoy_volatility" => 0.08,
#   #   "revenue_yoy_cv" => 0.67,
#   #   "net_income_yoy_volatility" => 0.12,
#   #   "net_income_yoy_cv" => 0.85,
#   #   "stability_score" => 72,              # 0-100の総合安定性スコア
#   #   "volatility_periods" => 5,            # 算出に使用した期数
#   # }
def self.get_volatility_metrics(metrics, window: 5)
```

### 2. 対象指標

以下の指標についてボラティリティを算出:

| 指標 | 意味 | 安定=良い理由 |
|------|------|-------------|
| `roe` | 株主資本利益率 | 安定した資本効率は持続的な価値創造を示唆 |
| `operating_margin` | 営業利益率 | 安定した収益構造はビジネスモデルの堅牢性を示唆 |
| `net_margin` | 純利益率 | 特別損益の影響の少なさを示唆 |
| `revenue_yoy` | 売上成長率 | 安定成長は需要の予測可能性を示唆 |
| `net_income_yoy` | 純利益成長率 | 安定は利益の予測可能性を示唆 |

### 3. stability_score の算出

各指標のCVを元に、0〜100の安定性スコアを算出:

```ruby
# CVが低いほどスコアが高い
# 各指標のCVを [0, 1] の範囲にクリップし、(1 - CV) * 100 をベースに重み付け平均
# roe_cv: 30%, operating_margin_cv: 30%, revenue_yoy_cv: 20%, net_income_yoy_cv: 20%
```

### 4. data_json スキーマ拡張

```ruby
define_json_attributes :data_json, schema: {
  # ... 既存のスキーマ ...
  roe_volatility: { type: :decimal },
  roe_cv: { type: :decimal },
  operating_margin_volatility: { type: :decimal },
  operating_margin_cv: { type: :decimal },
  revenue_yoy_volatility: { type: :decimal },
  revenue_yoy_cv: { type: :decimal },
  net_income_yoy_volatility: { type: :decimal },
  net_income_yoy_cv: { type: :decimal },
  stability_score: { type: :integer },
  volatility_periods: { type: :integer },
}
```

### 5. CalculateFinancialMetricsJob への組み込み

- メトリクス計算時に、対象企業の過去N期分のFinancialMetricをロードし、ボラティリティを算出
- 3期未満のデータしかない場合はスキップ（volatility_periods に有効期数を記録）

## テスト

### FinancialMetric.get_volatility_metrics

- 正常系: 5期分のメトリクスから各指標のボラティリティが正しく算出されること
- 全期間同じ値の場合: 標準偏差=0, CV=0, stability_score=100 となること
- 大きくばらつく場合: stability_score が低い値となること
- 3期未満の場合: nil を返すこと
- 一部指標がnilの場合: その指標のボラティリティはnilとなり、stability_score はnilでない指標のみで算出されること

## 依存関係

- FinancialMetricの既存data_jsonスキーマの拡張
- CalculateFinancialMetricsJobの既存フローへの追加
- 過去のFinancialMetricデータが蓄積されている必要があるため、初回インポート完了後に有効
