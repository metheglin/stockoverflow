# データモデル拡張性レビュー

## 概要

今後30件以上のメトリクス追加・分析機能の実装が予定されている中で、現在の `financial_metrics.data_json` を中心としたデータモデルがスケールするか、アーキテクチャレビューをおこなう。

## レビュー対象

### 1. data_json の限界評価

- **クエリ性能**: SQLite の JSON関数（`json_extract`）を多用した場合のパフォーマンス特性
  - WHERE句でのJSON値フィルタリング（例: `json_extract(data_json, '$.per') < 15`）
  - ORDER BYでのJSON値ソート
  - インデックスの適用可否（SQLite generated columns + index の検討）
- **スキーマ管理**: 現在 JsonAttribute concern で型定義しているが、属性数が50以上になった場合の管理コスト
- **マイグレーション**: data_json 内のスキーマ変更（キー名変更、型変更等）の運用方法

### 2. テーブル分割の検討

以下のような分割パターンを比較検討:

- **現状維持**: financial_metrics テーブルの専用カラム + data_json に全て格納
- **カテゴリ別テーブル**: growth_metrics, valuation_metrics, risk_metrics 等に分割
- **EAVパターン**: company_metric_values (company_id, metric_type, fiscal_year_end, value) のような汎用テーブル
- **ハイブリッド**: 頻繁に検索される指標は専用カラム、それ以外はdata_json

### 3. 履歴・バージョニング

- メトリクス定義（計算式）が変更された場合の既存データの扱い
- 同じ期間のメトリクスを異なるバージョンの計算式で保持する必要性

### 4. パフォーマンスベンチマーク

- 上場企業約4000社 × 年4期 × 10年 = 約16万レコードを想定
- data_json に50属性を持つ場合のINSERT/SELECT性能
- 複数JSON属性を条件に用いたスクリーニングクエリの実行時間

## 成果物

- データモデル拡張方針のドキュメント
- 必要に応じてマイグレーション計画・DDLを含む DEVELOP TODO の作成

## 備考

- このレビューの結果は、メトリクス計算プラグインフレームワーク (20260321_1000) の設計にも反映される
- SQLite固有の制約と最適化手法を重点的に調査する
