# DEVELOP: 収益性・効率性指標のYoY変化量トラッキング拡張

## 概要

現在YoYトラッキングが売上・利益の成長率（5指標）に限定されているのを拡張し、収益性・効率性指標のYoY変化量もFinancialMetricに記録する。

## 背景・動機

現在 `FinancialMetric` で算出・保持しているYoY指標:
- `revenue_yoy`, `operating_income_yoy`, `ordinary_income_yoy`, `net_income_yoy`, `eps_yoy`

一方、以下の指標は当期の絶対値のみが保持されており、前年比変化量が記録されていない:
- `roe`, `roa`, `operating_margin`, `ordinary_margin`, `net_margin`

これにより、以下のようなスクリーニング・分析ができない:
- 「ROEが前年比で3ポイント以上改善した企業」
- 「営業利益率が2期連続で拡大している企業」
- 「ROAが悪化し続けている企業を除外する」

プロジェクトの目標である「あらゆる指標を分析の対象として履歴を保持し、推移やトレンドの転換がわかるようにしたい」を実現するには、収益性指標の変化量トラッキングが不可欠である。

## 追加指標（data_json拡張）

### ポイント変化量（percentage point delta）

成長率ではなくポイント差で記録する。ROEが8%→12%になった場合、「+50%の改善」ではなく「+4ポイントの改善」と記録する。これは収益性指標の変化を直感的に把握するための業界標準的な表現である。

1. **roe_delta**: 当期ROE - 前期ROE（ポイント差）
2. **roa_delta**: 当期ROA - 前期ROA（ポイント差）
3. **operating_margin_delta**: 当期営業利益率 - 前期営業利益率（ポイント差）
4. **ordinary_margin_delta**: 当期経常利益率 - 前期経常利益率（ポイント差）
5. **net_margin_delta**: 当期純利益率 - 前期純利益率（ポイント差）
6. **equity_ratio_delta**: 当期自己資本比率 - 前期自己資本比率（ポイント差）

### 連続改善カウント

7. **consecutive_margin_improvement**: 営業利益率が連続で改善している期数
   - operating_margin_delta > 0 の連続回数

## 実装方針

1. **FinancialMetric にクラスメソッドを追加**:
   - `self.get_profitability_delta_metrics(current_fv, previous_fv, previous_metric)`
   - current_fv / previous_fv: FinancialValue（率の算出に必要）
   - previous_metric: 前期のFinancialMetric（consecutive_margin_improvement算出に必要）
   - 返り値: 上記7指標のHash

2. **CalculateFinancialMetricsJob への組み込み**:
   - 既存の get_profitability_metrics の算出後に追加実行
   - 前期の FinancialValue は既に取得済みのためパフォーマンス影響は軽微

3. **data_json スキーマへの追加**:
   - FinancialMetric の define_json_attributes に7指標を追加

4. **ScreeningQuery への反映**:
   - data_json内の指標もフィルタ可能にする拡張が必要（analysis_query_layer実装後）

## テスト

- `FinancialMetric.get_profitability_delta_metrics`:
  - 当期ROE=12%, 前期ROE=8% のとき roe_delta=4.0 であること
  - 当期営業利益率=15%, 前期営業利益率=18% のとき operating_margin_delta=-3.0 であること
  - 前期FVがnilの場合に全てnilを返すこと
  - 当期・前期の net_sales が 0 の場合にマージン系がnilとなること
- `consecutive_margin_improvement`:
  - 前期 consecutive_margin_improvement=2 かつ当期 operating_margin_delta>0 のとき 3 を返すこと
  - 当期 operating_margin_delta<=0 のとき 0 にリセットされること

## 関連TODO

- `dev_extend_financial_health_metrics` - 拡張ヘルス指標と組み合わせて総合的な改善/悪化判断に利用
- `dev_metric_trend_classification` - マージン変化のトレンド分類に活用
- `dev_growth_acceleration_metrics` - 成長加速度と収益性改善を組み合わせた分析
- `dev_analysis_query_layer` - ScreeningQueryのフィルタ条件として利用
