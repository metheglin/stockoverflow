# WORKLOG: SQLiteクエリ性能最適化

作業日時: 2026-03-25 06:58 UTC

## 作業の概要

TODOファイル `20260319_1605_improve_sqlite_query_performance_DEVELOP` にしたがい、SQLiteの設定およびインデックス戦略を見直し、分析クエリの性能を最適化した。

## 考えたこと・判断

### SQLiteプラグマ設定について

- Rails 8.1のデフォルト設定にはSQLiteプラグマ最適化が含まれていないことを確認
- `database.yml` の `pragmas:` キーを使用する方法を採用（initializer方式よりRails標準的）
- 設定したプラグマ:
  - `journal_mode: wal` - WALモードによる読み書き並行性向上
  - `synchronous: normal` - WALモードとの組み合わせで安全かつ高速
  - `cache_size: -64000` - 64MBキャッシュ
  - `mmap_size: 268435456` - 256MBメモリマップI/O

### インデックス追加について

既存インデックスとの重複を分析し、以下の判断をおこなった:

- `daily_quotes (company_id, traded_on)` → 既にユニークインデックスでカバー済み。**追加不要**
- `financial_metrics` のタイムライン向けインデックス → 既存ユニークインデックスは `(company_id, fiscal_year_end, scope, period_type)` の順序。`WHERE company_id=? AND scope=? AND period_type=? ORDER BY fiscal_year_end` パターンには `(company_id, scope, period_type, fiscal_year_end)` 順が最適。**追加**
- `financial_values` にも同様のタイムラインインデックスを**追加**
- スクリーニング向け複合インデックスを3種（売上成長・利益成長・キャッシュフロー）**追加**

### EXPLAIN QUERY PLANの確認結果

全ての主要分析クエリがインデックスを活用し、フルテーブルスキャンが発生しないことを確認:
- Timeline → `SEARCH USING INDEX idx_financial_metrics_timeline`
- Screening → `SEARCH USING INDEX idx_financial_metrics_screening_revenue`
- Cash flow → `SEARCH USING INDEX idx_financial_metrics_cashflow`
- Daily quotes → `SEARCH USING INDEX index_daily_quotes_on_company_id_and_traded_on`

## 作業内容

### 1. SQLiteプラグマ設定 (`config/database.yml`)
- `default:` セクションに `pragmas:` を追加

### 2. マイグレーション (`db/migrate/20260325065540_add_analytics_indexes_to_financial_metrics.rb`)
追加したインデックス:
- `idx_financial_metrics_timeline` - (company_id, scope, period_type, fiscal_year_end)
- `idx_financial_metrics_screening_revenue` - (scope, period_type, consecutive_revenue_growth, revenue_yoy)
- `idx_financial_metrics_screening_profit` - (scope, period_type, consecutive_profit_growth)
- `idx_financial_metrics_cashflow` - (scope, period_type, operating_cf_positive, investing_cf_negative)
- `idx_financial_values_timeline` - (company_id, scope, period_type, fiscal_year_end)

### 3. ベンチマークRakeタスク (`lib/tasks/benchmark.rake`)
- `rake benchmark:queries` で主要分析クエリの実行時間を計測
- プラグマ設定確認・テーブル行数表示・EXPLAIN QUERY PLAN表示・実行時間計測を一括実行
- `ITERATIONS` 環境変数で反復回数を指定可能（デフォルト10回）

### 4. テスト
- 既存テスト全245件パス（0 failures, 5 pending）
- pendingはcredentials未設定によるもので本変更と無関係
