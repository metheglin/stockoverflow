# DEVELOP: 経営陣の業績予想バイアス・プロファイリング

## 概要

経営陣が開示する業績予想と実績の乖離パターンを統計的に分析し、各企業の「予想傾向」をプロファイルとして分類・保存する。保守的に予想する企業（常に上振れ）と楽観的に予想する企業（常に下振れ）を識別可能にする。

## 背景・動機

既存TODOとの関連:
- `dev_forecast_revision_tracking`: 業績予想の修正イベントの追跡（いつ・どの程度修正されたか）
- `dev_management_forecast_accuracy_profile`: 個別期間の予想精度の計測

**本TODOの差別化ポイント**: 個別の予想精度ではなく、**複数期間にわたる系統的なバイアスパターン**を分析する。

例:
- 企業A: 過去5期の売上予想が実績比 -5%, -8%, -3%, -6%, -4% → 保守バイアス（平均-5.2%）
- 企業B: 過去5期の売上予想が実績比 +3%, -2%, +5%, +1%, +4% → 楽観バイアス（平均+2.2%）
- 企業C: 過去5期の売上予想が実績比 -1%, +1%, 0%, -2%, +1% → 中立（精度が高い）

この情報は投資判断において極めて有用:
- 保守バイアスの企業が予想を出すと「上振れ余地あり」と判断できる
- 楽観バイアスの企業が予想を出すと「達成困難リスクあり」と判断できる
- プロジェクト目標「飛躍前の変化」: 予想バイアスのパターンが変化した（保守→精度向上 = 経営の質的変化の可能性）

## 実装内容

### 1. FinancialMetric にクラスメソッドを追加

```ruby
# 経営陣の業績予想バイアスを分析する
#
# @param financial_values [Array<FinancialValue>] 直近N期分のFinancialValue（古い順）
# @return [Hash] バイアスプロファイル（data_json格納用）
#
# 例:
#   values = company.financial_values.consolidated.annual.order(:fiscal_year_end).last(5)
#   result = FinancialMetric.get_forecast_bias_profile(values)
#   # => {
#   #   "revenue_forecast_bias" => -0.052,         # 売上予想の平均乖離率（負=保守）
#   #   "operating_income_forecast_bias" => -0.08,  # 営業利益予想の平均乖離率
#   #   "net_income_forecast_bias" => -0.06,        # 純利益予想の平均乖離率
#   #   "forecast_bias_consistency" => 0.85,        # バイアスの一貫性（0-1）
#   #   "forecast_bias_type" => "conservative",     # "conservative"|"optimistic"|"neutral"|"erratic"
#   #   "forecast_bias_periods" => 5,               # 分析に使用した期数
#   # }
def self.get_forecast_bias_profile(financial_values)
```

### 2. バイアス算出ロジック

#### 個別期間の乖離率

```
bias_rate = (forecast - actual) / |actual|
```

- `forecast`: FinancialValueの `forecast_net_sales`, `forecast_operating_income`, `forecast_net_income`（data_json内）
- `actual`: FinancialValueの `net_sales`, `operating_income`, `net_income`（固定カラム）
- 正の値 = 予想が実績を上回る = 楽観バイアス
- 負の値 = 予想が実績を下回る = 保守バイアス

#### 注意: 予想値と実績値の期間対応

- 予想は通常「前年度の決算発表時に公表される翌期予想」
- したがって、ある期のFinancialValueのforecast_*と、翌期のFinancialValueのactualを比較する必要がある
- `financial_values[i].forecast_net_sales` vs `financial_values[i+1].net_sales` の比較

#### バイアスタイプの分類

| タイプ | 条件 |
|--------|------|
| `conservative` | 平均乖離率 < -3% かつ一貫性 > 0.6 |
| `optimistic` | 平均乖離率 > +3% かつ一貫性 > 0.6 |
| `neutral` | 平均乖離率が ±3% 以内 |
| `erratic` | 一貫性 ≤ 0.6（バイアスの方向が不安定） |

#### 一貫性スコア (forecast_bias_consistency)

- 乖離率の符号の一貫性を測定
- 全期間同じ符号（例: 全て負）なら 1.0
- 半々なら 0.5
- 算出: `同じ符号の期数 / 全期数`

### 3. data_json スキーマ拡張

FinancialMetric の data_json に追加:

```ruby
revenue_forecast_bias: { type: :decimal },
operating_income_forecast_bias: { type: :decimal },
net_income_forecast_bias: { type: :decimal },
forecast_bias_consistency: { type: :decimal },
forecast_bias_type: { type: :string },
forecast_bias_periods: { type: :integer },
```

### 4. CalculateFinancialMetricsJob への組み込み

- メトリクス算出時に過去5期分のFinancialValueを取得
- forecast_* フィールドが存在するレコードが3期分以上ある場合のみバイアス算出
- 結果を当期の FinancialMetric.data_json にマージ

## テスト

### FinancialMetric.get_forecast_bias_profile

- 正常系（保守バイアス）: 全期間で予想 < 実績のとき、bias < 0 かつ type = "conservative"
- 正常系（楽観バイアス）: 全期間で予想 > 実績のとき、bias > 0 かつ type = "optimistic"
- 中立ケース: 乖離率が小さいとき type = "neutral"
- 不安定ケース: 乖離の符号が期間ごとに変わるとき type = "erratic"
- 予想値なしのケース: forecast_*がnilの期間はスキップされること
- 期数不足のケース: 有効データが3期未満のときnilを返すこと

## 依存関係

- FinancialValue の data_json に forecast_net_sales, forecast_operating_income, forecast_net_income が格納されていること（ImportJquantsFinancialDataJobで取り込み済み）
- 過去データの蓄積が前提（最低3期分の予想・実績対が必要）
