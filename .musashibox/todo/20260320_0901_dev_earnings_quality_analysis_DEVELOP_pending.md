# TODO: 利益の質・アクルーアル分析メトリクスの追加

## 概要

営業キャッシュフローと純利益の乖離度合い（アクルーアル）を分析するメトリクスをFinancialMetricに追加し、利益の質を定量的に評価する。

## 背景・課題

現在のFinancialMetricでは成長性（YoY）、収益性（ROE/ROA/マージン）、CF分析（フリーCF/正負フラグ）、バリュエーション指標が算出されているが、「利益の質（Earnings Quality）」を直接評価する指標がない。

利益の質の分析は以下のプロジェクト目標に直結する:
- **連続増収増益企業のスクリーニング精度向上**: 見かけ上の増益が会計上の操作による場合（高アクルーアル）と、実際にキャッシュを伴う場合を区別
- **飛躍前兆の検出**: 利益の質が改善し始めた（現金転換率が向上した）企業は、持続的な成長に入る可能性が高い
- **リスク回避**: アクルーアル比率が高い企業は将来の業績下方修正リスクが高いことが学術的に実証されている

## 実装方針

### FinancialMetricへの追加指標（data_json拡張）

以下の指標を `FinancialMetric.data_json` に追加する:

1. **cash_conversion_ratio** (現金転換率)
   - 算出: `operating_cf / net_income`
   - 解釈: 1.0以上が健全。純利益に対してどれだけキャッシュを生み出しているか

2. **accrual_ratio** (アクルーアル比率)
   - 算出: `(net_income - operating_cf) / total_assets`
   - 解釈: 低いほど利益の質が高い。高い場合は収益認識が現金回収に先行している

3. **cf_to_income_gap** (CF-利益乖離額)
   - 算出: `operating_cf - net_income`
   - 解釈: プラスが健全（CFが利益を上回る）。マイナスが大きい場合は要注意

4. **cf_to_income_gap_yoy** (CF-利益乖離の前年比変化)
   - 算出: 当期cf_to_income_gap - 前期cf_to_income_gap
   - 解釈: 改善傾向か悪化傾向かを追跡

### 実装箇所

- `FinancialMetric` モデルに `self.get_earnings_quality_metrics(fv, previous_fv)` クラスメソッドを追加
- `CalculateFinancialMetricsJob` の算出パイプラインに組み込み
- data_jsonスキーマに上記4指標を追加

## テスト

- `FinancialMetric.get_earnings_quality_metrics` のユニットテスト
  - 正常系: 各指標の正しい算出
  - net_income=0の場合（cash_conversion_ratio算出不可 → nil）
  - total_assets=0の場合（accrual_ratio算出不可 → nil）
  - operating_cf=nilの場合（全指標nil）
  - 前期データなしの場合（cf_to_income_gap_yoyのみnil）

## 依存関係

- 既存のFinancialMetric, FinancialValue, CalculateFinancialMetricsJobに追加実装
- 新テーブル不要
