# PLAN: コアユースケース実現のための最短実行ロードマップ

## 概要

125件以上のpending TODOの中から、プロジェクトの3つのコアユースケースを**最短で動作可能にする**ために必要なTODOの依存関係を分析し、フェーズ分けした実行ロードマップを作成する。

## 背景・動機

### 現状

- データ基盤（モデル、API クライアント、インポートジョブ、メトリクス計算）は完成
- しかし**3つのコアユースケースを実行する手段が一切存在しない**（コントローラー、Rake タスク、Rails console 用のクエリメソッドがない）
- 125件以上の pending TODO が存在するが、優先順位が不明確で、どれから着手すべきかの指針がない

### コアユースケース（CLAUDE.md より）

1. **6期連続増収増益の企業を一覧し、増収率が高い順に並べる**
2. **営業CFプラスかつ投資CFマイナスの企業のうち、FCFがプラスに転換した企業を一覧する**
3. **ある企業の業績飛躍直前にどのような決算・財務上の変化があったかを調べる**

### 既存TODOとの関係

このPLAN TODOは**新たな機能を設計するものではなく**、既存TODOの最適な実行順序と最小限の組み合わせを特定するメタ計画である。

## 設計すべき項目

### 1. ユースケース別の依存TODO特定

各ユースケースを実現するために**必須な**既存TODOを洗い出す。「あると良い」TODOは含めない。

#### ユースケース1に必要な機能

- [確認] `FinancialMetric.consecutive_revenue_growth` / `consecutive_profit_growth` は既に算出済み
- [必要] 各企業の最新通期メトリクスを取得するスコープ → `dev_company_latest_metric_screening` (20260322_1503)
- [必要] 結果を表示する方法 → `dev_screening_result_table_formatter` (20260321_1100) or Rake task
- [必要] 実行手段（Rake or Console） → `dev_rake_operations_tasks` (20260320_0902)
- [確認] `bugfix_metric_calculation_processing_order` (20260322_1700) - 正確なconsecutive_growth値の前提

#### ユースケース2に必要な機能

- [確認] `operating_cf_positive`, `investing_cf_negative`, `free_cf_positive` は既に算出済み
- [必要] 「プラスに転換」の検出 → 前期の `free_cf_positive` が false で当期が true
- [必要] 前期メトリクスとの比較手段 → `dev_metric_time_series_accessor` (20260322_1002) or カスタムクエリ
- [必要] ユースケース1と同じスクリーニング・表示基盤

#### ユースケース3に必要な機能

- [必要] 企業の全期間データを時系列で閲覧する手段 → `dev_company_financial_timeline_view` (20260320_1600) or `dev_company_financial_timeline_viewer` (20260321_0903)
- [必要] 複数指標の時系列アクセサ → `dev_metric_time_series_accessor` (20260322_1002)
- [必要] 企業検索手段 → `dev_company_search_and_lookup` (20260321_1403) or securities_code直接指定

### 2. 最短経路の特定

上記から、全3ユースケースに共通する最小限のTODOセットを特定する:

- **Phase 0 (バグ修正)**: `bugfix_metric_calculation_processing_order` - データ正確性の前提
- **Phase 1 (基盤)**: 最新メトリクス取得 + 時系列アクセサ + 表示フォーマッタ
- **Phase 2 (実行手段)**: Rake タスクまたは console ショートカット
- **Phase 3 (ユースケース固有)**: FCF転換検出、タイムラインビュー

### 3. 各フェーズの工数見積もりと依存関係図

- TODO間の依存関係を明確にし、並行実施可能なものを特定
- 各TODOの実装ボリューム（小/中/大）を評価

### 4. 対象外TODOの分類

Phase 1-3 に含まれないTODOを以下のカテゴリに分類:

- **Phase 4**: データ品質向上（検証・バリデーション系）
- **Phase 5**: 高度分析指標（F-Score、Z-Score、DCF等）
- **Phase 6**: UI/API / 運用基盤
- **保留**: 現時点では不要と判断されるもの

## 成果物

- フェーズ分けされた実行ロードマップ（各フェーズに含まれるTODOのリスト、依存関係、推奨実行順序）
- 各ユースケースの「最小動作」に必要なTODOの明確なリスト
- 必要に応じて新たな DEVELOP TODO

## 備考

- 既存TODOの内容を変更するものではなく、実行優先順位の整理に特化
- ロードマップはworklog等で文書化し、今後のTHINKセッションでの指針とする
