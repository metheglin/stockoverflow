# SQLiteクエリ性能最適化

## 概要

データ量の増加に備えて、SQLite の設定・インデックス戦略を見直し、主要クエリパターンの性能を最適化する。

## 背景

- 上場企業約4,000社 x 過去数年分の四半期/年次データで `financial_values` / `financial_metrics` は数万レコード規模になる
- `daily_quotes` は 4,000社 x 250営業日/年 = 年間100万レコード規模
- 分析クエリ（スクリーニング、ランキング、時系列取得）が頻繁に実行される想定
- 現在のインデックスはユニーク制約ベースだが、分析クエリに最適化されていない可能性がある

## 実装内容

### 1. SQLite プラグマ設定の確認・最適化

`config/database.yml` または初期化処理で以下を確認・設定:

- `PRAGMA journal_mode = WAL`: 読み書き並行性の向上
- `PRAGMA synchronous = NORMAL`: WALモードとの組み合わせで安全かつ高速
- `PRAGMA cache_size = -64000`: キャッシュサイズ拡大（64MB）
- `PRAGMA mmap_size = 268435456`: メモリマップI/O有効化（256MB）

### 2. 分析クエリ向けインデックス追加

現状のインデックスを確認し、以下のパターンに対応するインデックスを検討:

#### 時系列取得（企業別メトリクス推移）
```sql
-- company_id + scope + period_type + fiscal_year_end の順でソート取得
CREATE INDEX idx_financial_metrics_timeline
  ON financial_metrics (company_id, scope, period_type, fiscal_year_end);
```

#### スクリーニング（条件絞り込み + ソート）
```sql
-- 連続増収N期以上の企業をrevenue_yoyでソート
CREATE INDEX idx_financial_metrics_screening
  ON financial_metrics (scope, period_type, consecutive_revenue_growth, revenue_yoy);
```

#### 日次株価の期間取得
```sql
-- company_id + date の範囲検索
CREATE INDEX idx_daily_quotes_company_date
  ON daily_quotes (company_id, date);
```

### 3. クエリ実行計画の確認

- 主要クエリに対して `EXPLAIN QUERY PLAN` を実行し、フルスキャンが発生していないか確認
- 必要に応じてインデックスを追加・調整

### 4. パフォーマンスベンチマーク

- Rakeタスクとして簡易ベンチマークを作成
- 主要クエリの実行時間を計測・記録
- データ量の増加に伴う性能変化を追跡可能にする

## 注意事項

- 既存のユニークインデックスとの重複を避けること。ユニークインデックスがカバーしているクエリには追加不要
- インデックス追加は書き込み性能とのトレードオフ。インポートジョブの性能劣化が許容範囲か確認
- Rails 8.2 のデフォルト SQLite 設定を先に確認し、既に最適化されている項目はスキップ
- `db/schema.rb` の既存インデックス定義を確認してから作業すること
