# dev_metric_trend_classification

## 概要

企業の財務指標の時系列推移を分析し、トレンドの方向性を自動分類する。改善中・悪化中・安定・転換上昇・転換下降などのラベルを付与する。

## 背景・目的

数値の変化率（YoY）は既に算出されているが、「この企業の収益性は改善トレンドにあるのか、それとも悪化に転じたのか」という方向性の判定がない。特に「転換点」の検出は、プロジェクトの主要ユースケースである「業績飛躍の直前の変化を捉える」に直結する。

既存の `plan_trend_turning_point_detection` はPLANステータスであり、詳細なアルゴリズム設計を扱う。本TODOは基本的なトレンド分類ロジックの実装に焦点を当てる。

## 実装内容

- financial_metrics の data_json 内に、各主要指標のトレンド分類を格納
- 分類ラベル:
  - `improving` - 直近2-3期連続で改善
  - `deteriorating` - 直近2-3期連続で悪化
  - `stable` - 変化率が一定範囲内（例: ±5%以内）
  - `turning_up` - 悪化から改善に転換（直前期まで悪化、今期改善）
  - `turning_down` - 改善から悪化に転換（直前期まで改善、今期悪化）
  - `volatile` - 改善と悪化が交互に発生
- 対象指標:
  - revenue_yoy, operating_income_yoy, net_income_yoy, eps_yoy
  - operating_margin, roe, roa
  - free_cf
- CalculateFinancialMetricsJob内で、既存メトリクス算出後に追加計算として実装

## テスト

- 3期連続増収の企業に `improving` ラベルが付与されることを検証
- 悪化から改善に転じた企業に `turning_up` ラベルが付与されることを検証
- データが2期分しかない場合の挙動を検証

## 関連TODO

- `plan_trend_turning_point_detection` - より高度な転換点検出の設計（本TODOが基盤）
- `plan_screening_state_change_detection` - トレンド分類の変化をスクリーニング条件として利用
- `dev_company_financial_timeline_view` - タイムラインビューにトレンドラベルを含められる
