# dev: セクター相対指標の算出

## 概要

Company テーブルに sector_17_code / sector_33_code が保持されているが、現在のシステムではセクター内での相対的な位置づけを示す指標が一切計算されていない。スクリーニングにおいて「同業他社と比較して優れた企業」を発見するためのセクター相対指標を算出する。

## 背景

プロジェクトの想定ユースケース（注目すべき企業の一覧）を実現するには、絶対値の指標だけでなく、セクター内での相対的な優位性を評価する必要がある。
例えば、営業利益率20%が優秀かどうかは業種によって大きく異なる（製造業 vs IT vs 小売）。

## 実装内容

1. `FinancialMetric` の data_json に以下のセクター相対指標を追加:
   - `sector_roe_percentile`: セクター内ROEパーセンタイル（0-100）
   - `sector_operating_margin_percentile`: セクター内営業利益率パーセンタイル
   - `sector_revenue_yoy_percentile`: セクター内売上成長率パーセンタイル
   - `sector_median_roe`: 参照用にセクター中央値を保持
   - `sector_median_operating_margin`: 同上

2. 計算対象セクター分類:
   - 33業種分類（sector_33_code）をデフォルトとする
   - セクター内企業数が少ない場合（10社未満）は17業種分類（sector_17_code）にフォールバック

3. 計算タイミング:
   - CalculateFinancialMetricsJob の後処理として、全企業の指標計算完了後にバッチでセクター集計を実施
   - または独立したジョブとして `CalculateSectorMetricsJob` を新設

4. 対象期間:
   - 直近の annual period_type のみを対象（四半期は対象外）

## 利用想定

- 「セクター内ROE上位10%かつ増収率もセクター上位20%の企業」のスクリーニング
- 企業詳細表示で「同業種内での位置づけ」を可視化

## 関連ファイル

- `app/models/company.rb` （sector_17_code, sector_33_code）
- `app/models/financial_metric.rb` （data_json スキーマ拡張）
- `app/jobs/calculate_financial_metrics_job.rb` または新規ジョブ
