# Work Log

Claude's development work log for this project.

## 2026-03-12 BUGFIX: ImportJquantsFinancialDataJob 429エラー時のデータ欠損防止

### 作業概要

`ImportJquantsFinancialDataJob` において、429エラー（レート制限）がリトライ後も解消されない場合にジョブが次の日付に進んでしまい、データの欠損が発生する問題を修正した。

### 原因分析

前回の429エラー対策（faraday-retry設定修正・sleep追加）によりリトライは機能するようになったが、リトライが上限に達した場合の動作に問題が残っていた:

1. **`import_by_date` が全エラーをrescue**: APIエラー（429含む）が発生しても例外を握りつぶし、次の日付へ進行してしまう
2. **`record_sync_date` が常に `Date.current` を記録**: エラーで一部日付がスキップされても同期ポインタが当日まで進むため、次回実行時にスキップされた日付が永久に取り込まれない

### 修正内容

1. **`import_by_date`** - エラーrescueを除去
   - APIエラー（429等）を呼び出し元に伝播させ、ジョブを停止させる設計に変更
   - 個別レコードの処理エラーは `import_statement` 内で引き続きrescue

2. **`import_incremental`** - 最終成功日付の追跡
   - `@last_successful_date` で最後に成功した日付を追跡
   - `ensure` ブロックで最終成功日付まで同期日を記録（エラー時も正常時も）
   - 次回実行時は最終成功日付から再開されるため、データ欠損が発生しない

3. **`import_full`** - 429エラーの再raise
   - `Faraday::TooManyRequestsError` を明示的に再raiseし、ジョブを停止
   - その他のエラー（個別企業のAPI障害等）は従来どおりrescueして継続

4. **`perform`** - 構造変更
   - `record_sync_date` をモード別に適切なタイミングで呼び出し
   - `log_result` を `ensure` ブロックに移動し、エラー時もログが出力される設計に

5. **`record_sync_date`** - date引数の追加
   - 任意の日付を記録できるよう引数を追加（デフォルトは当日）

6. **`SLEEP_BETWEEN_REQUESTS`** - 1秒 → 2秒に増加
   - レート制限到達の頻度を低減

### 設計判断

- **429エラーはジョブ停止**: レート制限エラーはリトライ不可能な状態を示すため、無視して次に進むのではなくジョブを停止する。次回実行時に続きから再開できる方が運用上有用
- **同期日の記録にensureを使用**: 正常完了時も異常終了時も、最後に成功した日付まで確実に記録される
- **import_statementのrescueは維持**: 個別レコードの処理エラー（データ不整合等）はジョブ全体を止める必要がないため従来どおり

### テスト結果

- 全スイート: 102 examples, 0 failures, 5 pending
- pendingはcredentials/APIキー未設定によるもの（正当なskip）
- テスティング規約により、ジョブの稼働テストは記述しない

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/jobs/import_jquants_financial_data_job.rb` | 429エラー時のデータ欠損防止修正 |

## 2026-03-12 BUGFIX: ImportJquantsFinancialDataJob 429エラー修正

### 作業概要

`ImportJquantsFinancialDataJob.perform_now` 実行時に大半のAPIリクエストが429（Too Many Requests）エラーで失敗する問題を修正した。

### 原因分析

2つの原因が重なっていた:

1. **JquantsApi のリトライ設定不備**: faraday-retry の `exceptions` リストに `Faraday::TooManyRequestsError` が含まれていなかったため、429レスポンスが即座に例外として発生し、リトライされなかった。`retry_statuses` オプションは `raise_error` ミドルウェアとの併用時に機能しない（`raise_error` が先に例外を発生させるため）。

2. **ジョブのレート制限対策の欠如**: `ImportJquantsFinancialDataJob` の `import_incremental`（日付ごとのループ）と `import_full`（企業ごとのループ）で、API呼び出し間にsleepが一切なく、短時間に大量のリクエストが送信されていた。

### 修正内容

1. **`app/lib/jquants_api.rb`** - faraday-retry設定修正
   - `exceptions` に `Faraday::TooManyRequestsError` を追加し、429レスポンス時にリトライが発生するようにした
   - `max` を 2 → 4 に増加、`interval` を 3 → 2 に調整し、exponential backoff（2, 4, 8, 16秒）で429回復を待つ設計に変更

2. **`app/jobs/import_jquants_financial_data_job.rb`** - レート制限対策追加
   - `SLEEP_BETWEEN_REQUESTS = 1` 定数を追加
   - `import_incremental` と `import_full` の両モードでAPI呼び出し間にsleepを挿入

3. **`app/jobs/import_daily_quotes_job.rb`** - 同パターンの予防修正
   - `import_incremental` モードにも同様のsleepを追加（`import_full` は既に `SLEEP_BETWEEN_COMPANIES` 対応済み）

4. **`spec/lib/jquants_api_spec.rb`** - 429リトライテスト追加
   - Faradayスタブで初回429→2回目200のシナリオを検証するテストを追加

### テスト結果

- 全スイート: 102 examples, 0 failures, 5 pending
- JquantsApi: 12 examples, 0 failures, 4 pending（credentials未設定による正当なskip）
- 新規テスト: 429リトライ動作確認 1 example

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/lib/jquants_api.rb` | faraday-retry 429リトライ設定修正 |
| `app/jobs/import_jquants_financial_data_job.rb` | SLEEP_BETWEEN_REQUESTS追加 |
| `app/jobs/import_daily_quotes_job.rb` | incremental モードにsleep追加 |
| `spec/lib/jquants_api_spec.rb` | 429リトライテスト追加 |

## 2026-03-12 PLAN: 分析クエリレイヤー設計

### 作業概要

蓄積されたデータを分析・活用するためのクエリインターフェースの詳細設計をおこなった。CLAUDE.mdの3つのユースケースに対応するQueryObjectクラスと、将来の拡張に耐えうる汎用スクリーニング機能を設計した。

### 現状分析

- `companies`, `financial_values`, `financial_metrics`, `daily_quotes` の4テーブルにデータ蓄積基盤は整備済み
- `FinancialMetric` には連続増収増益期数、CF指標（boolean）、YoY成長率、収益性指標が格納済み
- しかしデータを分析するためのscope、QueryObject、時系列取得インターフェースが一切存在しない

### 設計内容

#### 1. モデル scope の追加

**FinancialMetric** (4 scope):
- `consolidated_annual`: 連結・通期の基本フィルタ
- `latest_period`: 企業ごとの最新期をサブクエリで取得
- `consecutive_growth(min_periods:)`: 連続増収増益フィルタ（既存DBインデックス活用）
- `healthy_cf`: 営業CF正・投資CF負のフィルタ

**Company** (3 scope):
- `by_sector_17(code)`: 17業種フィルタ
- `by_sector_33(code)`: 33業種フィルタ
- `by_market(code)`: 市場区分フィルタ

#### 2. QueryObject クラス設計

| クラス名 | 配置先 | ユースケース | 概要 |
|---------|--------|------------|------|
| `Company::ConsecutiveGrowthQuery` | `app/models/company/` | UC1 | N期連続増収増益企業を増収率順に一覧 |
| `Company::CashFlowTurnaroundQuery` | `app/models/company/` | UC2 | フリーCFがマイナス→プラスに転換した企業を検出 |
| `Company::FinancialTimelineQuery` | `app/models/company/` | UC3 | 特定企業の財務数値・指標の時系列推移を取得 |
| `Company::ScreeningQuery` | `app/models/company/` | 汎用 | パラメータベースの汎用スクリーニング |

#### 3. DBインデックス追加

- `financial_metrics`: CF条件の複合インデックス `(operating_cf_positive, investing_cf_negative, free_cf_positive)`
- `companies`: `sector_33_code`, `market_code` の単独インデックス

#### 4. 主要設計判断

- **前期比較はRubyレベル**: SQLite自己結合よりテスタビリティ・明快さを優先。最新期の企業数（最大約4,000件）でN+1のコストは許容範囲
- **latest_period scopeはサブクエリ方式**: `WHERE fiscal_year_end = (SELECT MAX(...) ...)` で効率的に最新期を取得
- **汎用ScreeningQueryはホワイトリスト方式**: フィルタ可能カラムを定数で定義しSQLインジェクション防止。Web APIパラメータとの自然な対応を想定
- **QueryObject配置先**: `app/models/company/` 配下に `Query` suffix付きで配置（rails.md規約準拠）

### テスト計画

- scopeテストは記述しない（testing.md規約準拠）
- QueryObject 4クラスについてテスト記述: 合計約17テスト項目を予定
- `extract_values` / `extract_metrics` / `load_previous_metric` / `apply_filters` / `build_scope` などの公開メソッドを重点テスト

### 成果物

| ファイル | 内容 |
|---------|------|
| `todo/20260312_1000_dev_analysis_query_layer_DEVELOP_pending.md` | 分析クエリレイヤー詳細実装仕様書（DEVELOP TODO） |
| `todo/20260310_1400_plan_analysis_query_layer_PLAN_done.md` | 元PLANのステータスをdoneに変更 |

## 2026-03-11 PLAN: データ量推計レポート作成

### 作業概要

日本の上場会社数・決算回数・取引日数などの公開情報に基づき、実装済みJOBを実行した際に各テーブルに登録されるレコード数を推計し、レポートとしてまとめた。

### 調査・推計内容

- 日本の上場企業数: TSE合計約3,850〜3,950社（プライム約1,650、スタンダード約1,600、グロース約600）
- 年間取引日数: 約245日
- 決算期分布: 3月決算が約65〜70%
- 四半期報告書制度改正（2024年4月）の影響: EDINET提出書類が年4回→年2回に減少
- JQUANTSプラン別のデータ提供範囲

### 推計結果（標準シナリオ）

| テーブル | 推計レコード数 |
|---------|-------------|
| companies | 約4,000件 |
| financial_reports | 約137,000件 |
| financial_values | 約224,000件 |
| financial_metrics | 約224,000件 |
| daily_quotes | 約5,300,000件 |
| application_properties | 2〜3件 |
| **合計** | **約5,889,000件** |

- daily_quotesが全体の約90%を占める最大テーブル
- SQLiteファイルサイズ推計: 約1.4〜2.0GB（インデックス含む）
- 最大シナリオ（Premium、長期データ）では合計約1,300万件、最小シナリオ（Free）では約100万件

### 成果物

| ファイル | 内容 |
|---------|------|
| `docs/record_volume_estimation.md` | データ量推計レポート |
| `todo/20260311_1055_research_records_PLAN_done.md` | TODOステータスをdoneに変更 |

## 2026-03-10 THINK: 追加開発TODO作成（指標拡張・セクター分析・CLIツール）

### 作業概要

前回のTHINK（次期開発TODO作成）で識別された4件のpending TODOに加え、さらにプロジェクトを前進させるために不足している要素を分析し、追加のTODOを3件作成した。

### 現状分析

- 前回のTHINKで作成された4件のTODO（分析クエリレイヤー設計、Web API設計、ジョブスケジューリング、データ整合性チェック）はすべてpending状態
- 14件の完了済みTODOによって、データ基盤（6テーブル、3 APIクライアント、5ジョブ）は整備済み
- テスト: 101 examples, 0 failures, 5 pending（credentials未設定による正当なskip）

### 識別した追加のギャップ

既存pending TODOがカバーしていない以下の領域を発見:

1. **指標算出の不完全性**
   - `FinancialMetric.data_json` スキーマに `ev_ebitda` が定義済みだが、算出ロジックが未実装
   - `FinancialValue.data_json` に業績予想データ（`forecast_net_sales` 等）が格納されているが、実績との比較分析（Earning Surprise）がおこなわれていない
   - これらはスクリーニングにおいて重要な指標であり、既存パイプラインの拡張で対応可能

2. **業種別比較の手段がない**
   - `companies` に `sector_17/sector_33` データが存在するが、業種別集計の仕組みがない
   - 個別企業のROEやPERが高いか低いかを業種平均と比較して判断できない
   - 「注目すべき企業を一覧」するためには業種内ポジションの把握が有益

3. **データ活用手段の即時的な不足**
   - Web API完成前にデータを活用する手段が一切ない
   - CLAUDE.mdの3つのユースケースを試行するためのツールがない
   - rakeタスクによるCLI分析ツールで即時にデータ活用可能にできる

### 作成したTODO

| ファイル | 種別 | 優先度 | 内容 |
|---------|------|--------|------|
| `20260310_1500_dev_extend_financial_metrics_DEVELOP_pending.md` | DEVELOP | 高 | EV/EBITDA算出・業績予想乖離率（Earning Surprise）の算出ロジック追加 |
| `20260310_1501_plan_sector_analysis_PLAN_pending.md` | PLAN | 中 | セクター・業種別分析基盤設計（業種別統計量の算出・保存・活用方法） |
| `20260310_1502_dev_data_export_cli_DEVELOP_pending.md` | DEVELOP | 中 | CLI分析ヘルパー・データエクスポート（rakeタスクによるスクリーニング・CSV出力） |

### 推奨される作業順序（既存pending TODO含む全体）

1. **分析クエリレイヤー設計**（PLAN）→ 詳細設計書に基づく実装（DEVELOP）
2. **指標算出拡張**（DEVELOP）← NEW: 既存パイプライン拡張のため独立して並行可能
3. **Web API設計**（PLAN）→ 詳細設計書に基づく実装（DEVELOP）※ 分析クエリレイヤーに依存
4. **CLI分析ツール**（DEVELOP）← NEW: 分析クエリレイヤー実装後
5. **ジョブスケジューリング・初期データロード**（DEVELOP）※ 独立して並行可能
6. **データ整合性チェック**（DEVELOP）※ 独立して並行可能
7. **セクター分析基盤設計**（PLAN）→ 実装（DEVELOP）※ 指標算出拡張の後が望ましい

## 2026-03-10 THINK: 次期開発TODO作成

### 作業概要

プロジェクトの現状を棚卸しし、CLAUDE.mdに記載されたプロジェクト目的・ユースケースの実現に必要な次期開発TODOを作成した。

### 現状分析

全14件の既存TODOがすべて完了済み。以下の基盤が整備されている:

- **データベース**: 6テーブル（companies, financial_reports, financial_values, financial_metrics, daily_quotes, application_properties）
- **APIクライアント**: EDINET API, JQUANTS API, EDINET XBRLパーサー
- **データ取り込みジョブ**: SyncCompaniesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob, ImportDailyQuotesJob, CalculateFinancialMetricsJob
- **テスト**: 101 examples, 0 failures, 5 pending（credentials未設定による正当なskip）

### 識別したギャップ

データの蓄積・指標算出基盤は完成しているが、プロジェクト目的である「特定の条件で絞り込み、注目すべき企業を一覧できるシステム」を実現するために以下が不足:

1. **分析クエリレイヤーが未実装**: CLAUDE.mdの3つのユースケース（連続増収増益、CF転換、業績転換点分析）を実行するためのスコープ・クエリオブジェクトが存在しない
2. **Web APIが未実装**: `config/routes.rb` にはヘルスチェックのみ。データにアクセスする手段がない
3. **ジョブスケジューリングが未設定**: 5つのジョブは実装済みだが定期実行の仕組みがない。初期データロード手順も未整備
4. **データ整合性チェックが未実装**: バッチの個別エラーは rescue して継続する設計だが、取り込み漏れや算出漏れを検知する仕組みがない

### 作成したTODO

| ファイル | 種別 | 優先度 | 内容 |
|---------|------|--------|------|
| `20260310_1400_plan_analysis_query_layer_PLAN_pending.md` | PLAN | 最高 | 分析クエリレイヤー設計（3つのユースケースに対応するスコープ・QueryObject設計） |
| `20260310_1401_plan_web_api_PLAN_pending.md` | PLAN | 高 | Web API設計（REST APIエンドポイント・シリアライザー・認証） |
| `20260310_1402_dev_job_scheduling_DEVELOP_pending.md` | DEVELOP | 中 | ジョブスケジューリング・初期データロード整備（Solid Queue定期実行、rakeタスク） |
| `20260310_1403_improve_data_integrity_check_DEVELOP_pending.md` | DEVELOP | 中 | データ整合性チェック・モニタリング（算出漏れ検出、同期状態確認） |

### 推奨される作業順序

1. **分析クエリレイヤー設計**（PLAN）→ 詳細設計書に基づく実装（DEVELOP）
2. **Web API設計**（PLAN）→ 詳細設計書に基づく実装（DEVELOP）※ 分析クエリレイヤーに依存
3. **ジョブスケジューリング・初期データロード**（DEVELOP）※ 独立して並行可能
4. **データ整合性チェック**（DEVELOP）※ 独立して並行可能

## 2026-03-10 DEVELOP: 指標算出ジョブ実装

### 作業概要

`financial_values` テーブルの財務数値から各種分析指標を算出し、`financial_metrics` テーブルに保存する `CalculateFinancialMetricsJob` を実装した。

### 実施内容

1. **FinancialMetric モデル拡張** (`app/models/financial_metric.rb`)
   - `compute_yoy(current, previous)`: YoY（前年同期比）算出。分母には前期の絶対値を使用
   - `safe_divide(numerator, denominator)`: 安全な除算（分母が0/nilの場合nil）
   - `get_growth_metrics(current_fv, previous_fv)`: 成長性指標算出（revenue_yoy, operating_income_yoy, ordinary_income_yoy, net_income_yoy, eps_yoy）
   - `get_profitability_metrics(fv)`: 収益性指標算出（roe, roa, operating_margin, ordinary_margin, net_margin）
   - `get_cf_metrics(fv)`: CF指標算出（free_cf, operating_cf_positive, investing_cf_negative, free_cf_positive）
   - `get_consecutive_metrics(growth_metrics, previous_metric)`: 連続増収増益期数算出
   - `get_valuation_metrics(fv, stock_price)`: バリュエーション指標算出（per, pbr, psr, dividend_yield → data_json格納）

2. **CalculateFinancialMetricsJob** (`app/jobs/calculate_financial_metrics_job.rb`)
   - `recalculate` パラメータ: trueの場合全レコード再計算、falseの場合は未算出または更新されたレコードのみ
   - `company_id` パラメータ: 特定企業のみ算出する場合に指定
   - 前期データ検索: `fiscal_year_end` の約1年前（±1ヶ月）の範囲で検索
   - 株価取得: 決算期末日の前後7日間で最も近い営業日の調整後終値を使用（SQLite JULIANDAY関数）
   - 個別レコードの算出失敗時はログに記録して次のレコードへ継続

3. **テスト** (`spec/models/financial_metric_spec.rb`)
   - `.compute_yoy`: 6 examples（正/負の成長率、赤字→黒字転換、0/nil処理）
   - `.safe_divide`: 4 examples（正常除算、0/nil分母・分子）
   - `.get_growth_metrics`: 2 examples（全YoY指標算出、前期nil）
   - `.get_profitability_metrics`: 2 examples（全収益性指標算出、0売上）
   - `.get_cf_metrics`: 3 examples（正フリーCF、負フリーCF、nil値）
   - `.get_consecutive_metrics`: 4 examples（増収時+1、減収時リセット、前期nil、YoY nil）
   - `.get_valuation_metrics`: 2 examples（全バリュエーション指標算出、株価nil）

### テスト結果

- 全スイート: 101 examples, 0 failures, 5 pending
- FinancialMetric: 23 examples, 0 failures
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/models/financial_metric.rb` | 指標算出クラスメソッド追加 |
| `app/jobs/calculate_financial_metrics_job.rb` | 指標算出ジョブ新規作成 |
| `spec/models/financial_metric_spec.rb` | FinancialMetric テスト新規作成 |

## 2026-03-10 DEVELOP: 株価データ取り込みジョブ実装

### 作業概要

JQUANTSの株価四本値API (`/v2/equities/bars/daily`) から日次株価データを取得し、`daily_quotes` テーブルに保存する `ImportDailyQuotesJob` を実装した。

### 実施内容

1. **DailyQuote モデル拡張** (`app/models/daily_quote.rb`)
   - `JQUANTS_FIELD_MAP`: V2 bars/dailyフィールド → daily_quotesカラムの対応マッピング（8フィールド: O, H, L, C, Vo, Va, AdjFactor, AdjC）
   - `JQUANTS_DATA_JSON_FIELDS`: data_jsonに格納するフィールド（AdjO, AdjH, AdjL, AdjVo）
   - `INTEGER_COLUMNS`: 整数変換するカラム（volume, turnover_value）
   - `DailyQuote.get_attributes_from_jquants(data)`: JQUANTSレスポンスから属性Hashを生成するクラスメソッド

2. **ImportDailyQuotesJob** (`app/jobs/import_daily_quotes_job.rb`)
   - 2つの実行モード: 差分更新（デフォルト）、全件取得（`full: true`）
   - 差分更新: 最終同期日から当日まで日付指定モードで取得。土日は自動スキップ
   - 全件取得: 全上場企業について銘柄指定で過去データを取得。レート制限対応（`SLEEP_BETWEEN_COMPANIES = 1`）
   - `from_date`, `to_date` パラメータで取得期間を指定可能
   - `api_key` パラメータ対応: nilの場合はcredentialsから取得
   - `application_properties`（kind: `jquants_sync`）で最終同期日を管理
   - 個別レコードの失敗時はログに記録して次のレコードへ継続

3. **テスト** (`spec/models/daily_quote_spec.rb`)
   - `DailyQuote.get_attributes_from_jquants`: 4 examples
     - 固定カラム8フィールドの変換検証
     - data_json 4フィールドの変換検証
     - volume/turnover_valueの整数変換検証
     - nil値のスキップ検証

### テスト結果

- 全スイート: 78 examples, 0 failures, 5 pending
- DailyQuote: 4 examples, 0 failures
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/models/daily_quote.rb` | JQUANTS フィールドマッピング定数・属性変換メソッド追加 |
| `app/jobs/import_daily_quotes_job.rb` | 株価データ取り込みジョブ新規作成 |
| `spec/models/daily_quote_spec.rb` | DailyQuote テスト新規作成 |

## 2026-03-10 DEVELOP: EDINET決算データ取り込みジョブ実装

### 作業概要

EDINETの書類一覧APIから有価証券報告書・四半期報告書を検出し、XBRLデータを取得・パースして `financial_reports` / `financial_values` テーブルに保存する `ImportEdinetDocumentsJob` を実装した。

### 実施内容

1. **ImportEdinetDocumentsJob** (`app/jobs/import_edinet_documents_job.rb`)
   - EDINET書類一覧APIから対象日の書類を取得し、XBRLをダウンロード・パースして財務データを取り込む
   - `DOC_TYPE_REPORT_MAP`: docTypeCode → report_type の変換マッピング定数
   - `SLEEP_BETWEEN_DOCS = 4`, `SLEEP_BETWEEN_DAYS = 2`: EDINET APIレート制限対応
   - `from_date`, `to_date` パラメータで取得期間を指定可能。未指定時は `application_properties` (kind: `edinet_sync`) の `last_synced_date` から昨日まで
   - `api_key` パラメータ対応: nilの場合はcredentialsから取得
   - 企業検索: 証券コード（5桁正規化）→ EDINETコード → 新規作成のフォールバック
   - EDINETコード未設定の既存企業に対してEDINETコードを補完
   - データ補完戦略: 既存FinancialValue（JQUANTS由来）には拡張B/S項目のみマージ、新規の場合はXBRL抽出値で作成
   - エラーハンドリング: 日単位・書類単位でrescueし、バッチ全体を止めない設計
   - Tempfileの確実なクリーンアップ（ensureブロック）

2. **公開メソッド**（テスト可能な設計）
   - `normalize_securities_code(code)`: 証券コードの5桁正規化（4桁→末尾0追加、"0"/空文字→nil）
   - `determine_report_type(doc)`: docTypeCodeと期間からreport_typeを判定
   - `determine_quarter(doc)`: 四半期報告書の期間判定（月数差でq1/q2/q3/annual）

3. **テスト** (`spec/jobs/import_edinet_documents_job_spec.rb`)
   - `#normalize_securities_code`: 6 examples（4桁正規化、5桁そのまま、空文字列、nil、"0"、空白除去）
   - `#determine_report_type`: 8 examples（annual、semi_annual、四半期3種、不明コード）
   - `#determine_quarter`: 7 examples（q1/q2/q3/annual、nil日付、不正な日付）

### テスト結果

- 全スイート: 74 examples, 0 failures, 5 pending
- ImportEdinetDocumentsJob: 21 examples, 0 failures
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/jobs/import_edinet_documents_job.rb` | EDINET決算データ取り込みジョブ新規作成 |
| `spec/jobs/import_edinet_documents_job_spec.rb` | ImportEdinetDocumentsJob テスト新規作成 |

## 2026-03-09 DEVELOP: JQUANTS決算データ取り込みジョブ実装

### 作業概要

JQUANTSの財務情報サマリーAPI (`/v2/fins/summary`) から決算データを取得し、`financial_reports` / `financial_values` テーブルに保存する `ImportJquantsFinancialDataJob` を実装した。

### 実施内容

1. **FinancialValue モデル拡張** (`app/models/financial_value.rb`)
   - `JQUANTS_CONSOLIDATED_FIELD_MAP`: 連結決算のV2フィールド → financial_valuesカラムの対応マッピング（16フィールド）
   - `JQUANTS_CONSOLIDATED_DATA_JSON_MAP`: data_jsonに格納する連結予想・配当フィールド（6フィールド）
   - `JQUANTS_NON_CONSOLIDATED_FIELD_MAP`: 個別決算のNC*フィールド → カラムの対応マッピング（8フィールド）
   - `INTEGER_COLUMNS` / `DECIMAL_COLUMNS`: 型変換用のカラム分類定数
   - `FinancialValue.get_attributes_from_jquants(data, scope_type:)`: JQUANTSレスポンスから属性Hashを生成するクラスメソッド
   - `FinancialValue.parse_jquants_value(raw_value, column)`: 文字列値をカラム型に変換するクラスメソッド
   - `FinancialValue.parse_jquants_value_raw(raw_value)`: data_json用の型推定変換メソッド

2. **ImportJquantsFinancialDataJob** (`app/jobs/import_jquants_financial_data_job.rb`)
   - 3つの実行モード: 差分更新（デフォルト）、全件更新（`full: true`）、特定日指定（`target_date:`）
   - `import_statement`: 1件の財務情報サマリーからfinancial_report + financial_value（連結・個別）を作成/更新
   - JQUANTS由来doc_id生成: `JQ_{Code}_{CurFYEn}_{CurPerType}`
   - 既存data_jsonのマージ（EDINET由来の拡張データを保持）
   - `application_properties`（kind: `jquants_sync`）で最終同期日を管理
   - 個別レコードの失敗時はログに記録して次のレコードへ継続

3. **テスト** (`spec/models/financial_value_spec.rb`)
   - `FinancialValue.get_attributes_from_jquants`: 属性Hash生成テスト（5 examples）
     - 連結: 固定カラム16フィールドの変換検証
     - 連結: data_json 6フィールドの変換検証
     - 連結: 空文字列/nil のnil変換検証
     - 個別: NC*フィールド8フィールドの変換検証
     - 個別: data_jsonが設定されないことの検証
   - `FinancialValue.parse_jquants_value`: 型変換テスト（5 examples）
     - 整数カラム/小数カラム/空文字列/nil/負の値

### テスト結果

- 全スイート: 53 examples, 0 failures, 5 pending
- FinancialValue: 10 examples, 0 failures
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/models/financial_value.rb` | JQUANTS フィールドマッピング定数・属性変換メソッド追加 |
| `app/jobs/import_jquants_financial_data_job.rb` | JQUANTS決算データ取り込みジョブ新規作成 |
| `spec/models/financial_value_spec.rb` | FinancialValue テスト新規作成 |

## 2026-03-09 DEVELOP: 企業マスター同期ジョブ実装

### 作業概要

JQUANTSの上場銘柄一覧APIから企業マスター（`companies`テーブル）を同期する `SyncCompaniesJob` を実装した。

### 実施内容

1. **Company モデル拡張** (`app/models/company.rb`)
   - `JQUANTS_FIELD_MAP`: JQUANTS V2レスポンスフィールド → companiesカラムの対応マッピング定数
   - `JQUANTS_DATA_JSON_FIELDS`: data_jsonに格納するフィールド（Mrgn, MrgnNm）
   - `Company.get_attributes_from_jquants(data)`: JQUANTSレスポンスからCompany属性Hashを生成するクラスメソッド

2. **SyncCompaniesJob** (`app/jobs/sync_companies_job.rb`)
   - JQUANTS APIから上場銘柄一覧を全件取得し、`securities_code`をキーにupsert
   - JQUANTS一覧に存在しない既存上場企業を`listed: false`に更新（`mark_unlisted`）
   - `application_properties`に最終同期時刻を記録（`record_sync_time`）
   - 個別企業のDB保存失敗時はログに記録して次の企業へ継続（エラーハンドリング規約準拠）
   - `api_key`引数対応: nilの場合はcredentialsから取得

3. **テスト** (`spec/models/company_spec.rb`)
   - `Company.get_attributes_from_jquants`: 属性Hash生成テスト（3 examples）
     - 全フィールドの正しいマッピング検証
     - data_jsonフィールドの設定検証
     - 存在しないキーのスキップ検証

### テスト結果

- 全スイート: 43 examples, 0 failures, 5 pending
- Company: 3 examples, 0 failures
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/models/company.rb` | JQUANTS フィールドマッピング定数・属性変換メソッド追加 |
| `app/jobs/sync_companies_job.rb` | 企業マスター同期ジョブ新規作成 |
| `spec/models/company_spec.rb` | Company.get_attributes_from_jquants テスト |

## 2026-03-06 PLAN: データ取り込みパイプライン設計

### 作業概要

EDINET / JQUANTS から取得したデータをデータベースに取り込み、分析指標を算出するパイプラインの詳細設計をおこなった。5つのジョブの詳細設計書（DEVELOP TODO）を作成した。

### 設計内容

既存のAPIクライアント（`EdinetApi`, `JquantsApi`, `EdinetXbrlParser`）とDBスキーマ（`companies`, `financial_reports`, `financial_values`, `financial_metrics`, `daily_quotes`, `application_properties`）を前提に、以下のジョブを設計した。

#### 1. SyncCompaniesJob（企業マスター同期）
- JQUANTSの上場銘柄一覧から`companies`テーブルへupsert
- `Company.get_attributes_from_jquants` でV2フィールドマッピング
- JQUANTS一覧に存在しない既存上場企業の `listed: false` 更新
- 週次実行

#### 2. ImportJquantsFinancialDataJob（JQUANTS決算データ取り込み）
- JQUANTS財務情報サマリーから`financial_reports` + `financial_values`を作成
- `FinancialValue.get_attributes_from_jquants` で連結/個別のV2フィールドマッピング
- 差分更新モード（日付指定API）と全件更新モード（銘柄指定API）の2モード
- JQUANTS由来doc_id生成ルール: `JQ_{Code}_{FYEn}_{PerType}`
- 日次実行

#### 3. ImportEdinetDocumentsJob（EDINET決算データ取り込み）
- EDINET書類一覧APIから有報・四半報を検出、XBRL取得・パース
- JQUANTSデータの**補完**的位置づけ: 既存financial_valuesには拡張B/S項目のみマージ
- EDINETコードと証券コードの紐づけ
- 証券コード正規化（4桁→5桁）、四半期判定（期間月数ベース）
- レート制限対応（書類取得間4秒sleep）
- 日次実行

#### 4. ImportDailyQuotesJob（株価データ取り込み）
- JQUANTS株価四本値から`daily_quotes`テーブルへupsert
- `DailyQuote.get_attributes_from_jquants` でV2フィールドマッピング
- 差分取得（日付指定、土日スキップ）と全件取得（銘柄指定）の2モード
- 日次実行

#### 5. CalculateFinancialMetricsJob（指標算出）
- `financial_values`から各種分析指標を算出し`financial_metrics`に保存
- 成長性指標（YoY）: 前期±1ヶ月範囲で検索
- 収益性指標: ROE, ROA, 営業利益率等
- CF指標: フリーCF, 営業CF正負等
- 連続指標: 連続増収増益期数
- バリュエーション指標: PER, PBR, PSR（決算期末前後7日の株価使用）
- 算出ロジックは`FinancialMetric`モデルのクラスメソッドとして配置
- 決算データ取り込み後に日次実行

### 設計判断

- **JQUANTS優先方針**: JQUANTS構造化データを主ソースとし、EDINET XBRLは拡張B/S項目の補完に利用
- **エラーハンドリング**: 全ジョブで個別レコードの失敗をrescueしてログ記録、バッチ全体を止めない設計
- **application_properties活用**: edinet_sync/jquants_sync で最終同期日を管理し差分更新を実現
- **フィールドマッピング定数**: V2 APIの省略フィールド名のマッピングをモデル定数として管理
- **テスト方針**: 算出ロジック（モデルのクラスメソッド）を重点的にテスト、ジョブの稼働テストは記述しない

### 推奨される実装順序

1. SyncCompaniesJob（他ジョブの前提: companiesデータが必要）
2. ImportJquantsFinancialDataJob（主要財務データの蓄積）
3. ImportDailyQuotesJob（バリュエーション指標算出の前提）
4. ImportEdinetDocumentsJob（JQUANTS補完）
5. CalculateFinancialMetricsJob（全データ蓄積後に算出）

### 成果物

| ファイル | 内容 |
|---------|------|
| `todo/20260306_1700_dev_sync_companies_DEVELOP_pending.md` | 企業マスター同期ジョブ詳細設計 |
| `todo/20260306_1701_dev_import_jquants_financial_data_DEVELOP_pending.md` | JQUANTS決算データ取り込みジョブ詳細設計 |
| `todo/20260306_1702_dev_import_edinet_documents_DEVELOP_pending.md` | EDINET決算データ取り込みジョブ詳細設計 |
| `todo/20260306_1703_dev_import_daily_quotes_DEVELOP_pending.md` | 株価データ取り込みジョブ詳細設計 |
| `todo/20260306_1704_dev_calculate_financial_metrics_DEVELOP_pending.md` | 指標算出ジョブ詳細設計 |
| `todo/20260305_1004_plan_data_import_pipeline_PLAN_done.md` | 元PLANのステータスをdoneに変更 |

## 2026-03-06 DEVELOP: JQUANTS APIクライアント実装

### 作業概要

J-Quants API v2のHTTPクライアント（`JquantsApi`）を実装し、Faradayスタブによるユニットテストを整備した。

### 実施内容

1. **JquantsApi** (`app/lib/jquants_api.rb`)
   - J-Quants API v2へのHTTPリクエストクライアント
   - Faraday + faraday-retry によるHTTP通信・自動リトライ（max: 2, interval: 3s, backoff: 2倍）
   - 認証: `x-api-key` ヘッダー方式（V2 API）
   - `load_listed_info`: 上場銘柄一覧取得
   - `load_daily_quotes`: 株価四本値取得（from/to期間指定対応）
   - `load_financial_statements`: 財務情報サマリー取得
   - `load_earnings_calendar`: 決算発表予定日取得
   - `load_all_pages`: ページネーション自動処理（`pagination_key` 追跡・全ページ結合）
   - `PERIOD_TYPE_MAP`: CurPerType → report_type 変換マッピング定数
   - コーディング規約「汎用性と利便性」に準拠: `api_key`を引数で受け取り、`JquantsApi.default`でcredentialsから取得する便利メソッドを提供

2. **テスト** (`spec/lib/jquants_api_spec.rb`)
   - Faraday::Adapter::Test::Stubs を使ったユニットテスト（7テスト）
   - `load_listed_info`: 銘柄一覧取得・codeパラメータ指定・x-api-keyヘッダー検証
   - `load_daily_quotes`: 四本値取得・from/toパラメータ検証
   - `load_financial_statements`: 財務サマリー取得・codeパラメータ検証
   - `load_earnings_calendar`: 決算発表日取得
   - `load_all_pages`: ページネーション自動処理（2ページ結合）・単一ページ終了
   - 実APIテストはAPIキー設定時のみ実行される形で配置（3テスト）
   - `.default` メソッドはcredentials設定時のみ実行（1テスト）

### テスト結果

- 全スイート: 40 examples, 0 failures, 5 pending
- JquantsApi: 11 examples, 0 failures, 4 pending
- pendingはcredentials/APIキー未設定によるもの（正当なskip）

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/lib/jquants_api.rb` | J-Quants API v2 HTTPクライアント |
| `spec/lib/jquants_api_spec.rb` | JquantsApi テスト（スタブ+実API） |

## 2026-03-06 PLAN: JQUANTS APIクライアント設計

### 作業概要

J-Quants API v2の仕様を詳細調査し、APIクライアント（`JquantsApi`）の詳細設計書を作成した。

### 調査内容

- **J-Quants API v2仕様**: ベースURL `https://api.jquants.com/v2/`、V2認証方式（`x-api-key`ヘッダー、トークンリフレッシュ不要）、レスポンス形式の統一（`{ "data": [...], "pagination_key": "..." }`）、ページネーション機構
- **V1→V2移行の変更点**: 認証方式の変更（トークン方式→APIキー方式）、全エンドポイントのパス変更（例: `/v1/listed/info` → `/v2/equities/master`）、レスポンスフィールド名の省略形への変更（例: `CompanyName` → `CoName`、`Open` → `O`）
- **レート制限**: Free=5req/min, Light=60, Standard=120, Premium=500
- **主要エンドポイント**: 上場銘柄一覧(`/v2/equities/master`)、株価四本値(`/v2/equities/bars/daily`)、財務情報サマリー(`/v2/fins/summary`)、決算発表予定日(`/v2/equities/earnings-calendar`)

### 設計判断

- **V2 API採用**: 2025年12月22日以降の新規ユーザーはV2のみ利用可能。V2は `x-api-key` ヘッダー方式でトークン管理が不要なため、クライアント実装がシンプル
- **ページネーション自動処理**: `load_all_pages` メソッドで `pagination_key` を自動追跡し、全ページを結合して返す設計。呼び出し元がページネーションを意識しなくてよい
- **EdinetApiとの設計統一**: 同じFaradayベースの構成、同じ便利メソッドパターン（`JquantsApi.default`）、同じリトライ設定を採用
- **EDINETとのデータ連携方針**: companies テーブルの `securities_code` で紐づけ。JQUANTSの構造化データを優先的に利用し、EDINET XBRL拡張要素で補完する方針
- **V2省略フィールド名のマッピング**: V2レスポンスの省略フィールド名とDBカラムの対応表を詳細に文書化

### 成果物

| ファイル | 内容 |
|---------|------|
| `todo/20260306_1600_dev_jquants_api_client_DEVELOP_pending.md` | JQUANTS APIクライアント詳細実装仕様書（DEVELOP TODO） |
| `todo/20260305_1003_plan_jquants_api_client_PLAN_done.md` | 元PLANのステータスをdoneに変更 |

### 設計したクラス

| クラス名 | 配置先 | 概要 |
|---------|--------|------|
| JquantsApi | app/lib/jquants_api.rb | J-Quants API v2 HTTPクライアント。上場銘柄一覧・株価四本値・財務サマリー・決算発表日の取得 |

## 2026-03-06 BUGFIX: EDINET APIクライアント バグ修正・テスト整備

### 作業概要

EdinetApi のURLパス解決バグを修正し、EdinetApi・EdinetXbrlParser 両方のテストを実際に動作を検証するテストに書き直した。

### 発見したバグ

**EdinetApi: URLパス解決の不具合（致命的）**

`BASE_URL = "https://api.edinet-fsa.go.jp/api/v2"` に対して、`get("/documents.json", ...)` のように先頭 `/` 付きの絶対パスを使用していたため、Faradayがベースパス `/api/v2` を無視し、`https://api.edinet-fsa.go.jp/documents.json` にリクエストを送信していた。正しくは `/api/v2/documents.json` にリクエストすべきであり、全てのAPIリクエストが誤ったURLに送られていた。

### 修正内容

1. **`app/lib/edinet_api.rb`**
   - `BASE_URL` に末尾スラッシュを追加: `"https://api.edinet-fsa.go.jp/api/v2/"`
   - 全てのパス引数から先頭 `/` を除去し相対パスに変更:
     - `"/documents.json"` → `"documents.json"`
     - `"/documents/#{doc_id}"` → `"documents/#{doc_id}"`

2. **`spec/lib/edinet_api_spec.rb`** 全面書き直し
   - Faraday::Adapter::Test::Stubs を使ったユニットテストを新規追加（7テスト）
   - リクエスト先URL・パラメータ（Subscription-Key, date, type）を実際に検証
   - `load_documents`, `load_target_documents`, `load_xbrl_zip`, `load_csv_zip` の各メソッドをテスト
   - 実APIテストはAPIキー設定時のみ実行される形で残存（`context ... if:` 形式）

3. **`spec/lib/edinet_xbrl_parser_spec.rb`** 全面書き直し
   - テスト内でZIPファイルを動的に作成するヘルパーメソッド `create_xbrl_zip` を追加
   - `#parse` のフルフローテストを追加（ZIPからXBRL読み出し→パース→連結/個別抽出）
   - `#load_xbrl_from_zip` のテストを追加
   - 既存の `#find_element_value`, `#extract_values` テストも維持（skipなし）

### 前回の問題点

- EdinetApiのテストは全て `skip "EDINET API key not configured"` で実行されておらず、バグが検出されなかった
- EdinetXbrlParserの `#parse` テストも `skip "XBRLフィクスチャが未配置"` でスキップされていた
- テスト結果 "23 examples, 0 failures" は技術的に正しいが、実質的にEdinetApiの動作検証は0件だった

### テスト結果

- 29 examples, 0 failures, 1 pending
- pendingは `.default` メソッドのcredentials未設定によるもの（正当なskip）

### 成果物

| ファイル | 変更内容 |
|---------|---------|
| `app/lib/edinet_api.rb` | URLパス解決バグ修正 |
| `spec/lib/edinet_api_spec.rb` | Faraday stubベースのユニットテストに書き直し |
| `spec/lib/edinet_xbrl_parser_spec.rb` | 動的ZIP生成によるフルフローテストに書き直し |

## 2026-03-06 DEVELOP: EDINET APIクライアント・XBRLパーサー実装

### 作業概要

EDINET API v2のHTTPクライアント（`EdinetApi`）およびXBRLパーサー（`EdinetXbrlParser`）を実装した。

### 実施内容

1. **Gemfile更新**
   - `rubyzip` gemを追加（ZIPファイル展開用）
   - `bundle install` 実行

2. **EdinetApi** (`app/lib/edinet_api.rb`)
   - EDINET API v2へのHTTPリクエストクライアント
   - Faraday + faraday-retry によるHTTP通信・自動リトライ
   - `load_documents`: 書類一覧取得（JSON）
   - `load_target_documents`: 対象書類種別（有価証券報告書・四半期報告書等）のみ絞り込み
   - `load_xbrl_zip`: XBRLデータのZIPダウンロード
   - `load_csv_zip`: CSVデータのZIPダウンロード
   - コーディング規約「汎用性と利便性」に準拠: `api_key`を引数で受け取り、`EdinetApi.default`でcredentialsから取得する便利メソッドを提供

3. **EdinetXbrlParser** (`app/lib/edinet_xbrl_parser.rb`)
   - Nokogiriベースの自前XBRLパーサー
   - ZIP展開 → XBRLインスタンスファイル読み出し → 財務数値抽出
   - `ELEMENT_MAPPING`: P/L・B/S・C/F固定カラム対応のXBRL要素マッピング（候補配列で企業ごとの勘定科目差異に対応）
   - `EXTENDED_ELEMENT_MAPPING`: data_json格納用の拡張要素マッピング
   - `CONTEXT_PATTERNS`: コンテキストIDの正規表現で連結/個別を分離
   - 名前空間未定義時の`Nokogiri::XML::XPath::SyntaxError`を安全にハンドリング

4. **テスト**
   - `spec/lib/edinet_api_spec.rb`: APIキー設定時のみ実行される実API呼び出しテスト（4 examples, 4 pending）
   - `spec/lib/edinet_xbrl_parser_spec.rb`: インラインXMLによる単体テスト（10 examples, 0 failures, 1 pending）
     - `find_element_value`: 値抽出、候補配列フォールバック、nil返却、マイナス値、コンテキストフィルタリング
     - `extract_values`: 連結・個別抽出、主要項目nil判定、拡張要素格納
   - 全体: 23 examples, 0 failures

5. **フィクスチャ・.gitignore**
   - `spec/fixtures/edinet/` ディレクトリ作成
   - `.gitignore` にXBRLフィクスチャZIPファイルの除外を追加

### 修正・対応事項

- `find_element_value`で名前空間が未定義のXML（テスト用の最小XMLなど）に対してxpath実行時に`Nokogiri::XML::XPath::SyntaxError`が発生する問題を修正。rescue句でスキップしnilを返すよう対応

### 成果物

| ファイル | 内容 |
|---------|------|
| `Gemfile` | rubyzip gem追加 |
| `app/lib/edinet_api.rb` | EDINET API v2 HTTPクライアント |
| `app/lib/edinet_xbrl_parser.rb` | XBRLパーサー |
| `spec/lib/edinet_api_spec.rb` | EdinetApi テスト |
| `spec/lib/edinet_xbrl_parser_spec.rb` | EdinetXbrlParser テスト |
| `spec/fixtures/edinet/.keep` | テストフィクスチャディレクトリ |
| `.gitignore` | XBRLフィクスチャZIP除外追加 |

## 2026-03-05 DEVELOP: データベーススキーマ実装

### 作業概要

データベーススキーマの詳細設計書に基づき、マイグレーション・モデル・concern・テストを実装した。

### 実施内容

1. **JsonAttribute concern** (`app/models/concerns/json_attribute.rb`)
   - JSON型カラムにスキーマを定義し、getter/setterを自動生成するconcern
   - SQLiteがJSON型をtext列として格納する問題に対応するため、String型のJSON値もパースするよう実装

2. **マイグレーション6件**（`db/migrate/`）
   - `create_companies`: 企業マスター。edinet_code/securities_codeにunique index
   - `create_financial_reports`: 決算報告書メタデータ。report_type/source enum対応
   - `create_financial_values`: 財務数値。P/L・B/S・C/F主要16カラム + JSON拡張
   - `create_financial_metrics`: 分析指標。YoY成長率・収益性・CF指標・連続指標
   - `create_daily_quotes`: 株価四本値。バリュエーション指標算出用
   - `create_application_properties`: アプリ全体メタデータ管理

3. **モデル6件**
   - `Company`, `FinancialReport`, `FinancialValue`, `FinancialMetric`, `DailyQuote`, `ApplicationProperty`
   - enum定義、association、JsonAttribute連携を実装

4. **テスト** (`spec/models/concerns/json_attribute_spec.rb`)
   - getter: Hash/nil/未設定キーの各パターン
   - setter: 新規設定/既存値保持/上書き
   - String JSON: SQLite互換のString型JSON値のパース
   - class_attribute: スキーマ定義の保持
   - 9 examples, 0 failures

### 修正・対応事項

- `application_properties.data_json` のデフォルト値を `"{}"` (String) → `{}` (Hash) に修正。SQLiteではJSON型がtext列となり、String値がそのまま返される問題があった
- JsonAttribute concernに `parse_#{column_name}` ヘルパーを追加し、String型JSON値をHashに変換する防御的実装とした

### 成果物

| ファイル | 内容 |
|---------|------|
| `app/models/concerns/json_attribute.rb` | JSON属性アクセサconcern |
| `db/migrate/20260305110039_create_companies.rb` | companiesテーブル |
| `db/migrate/20260305110043_create_financial_reports.rb` | financial_reportsテーブル |
| `db/migrate/20260305110044_create_financial_values.rb` | financial_valuesテーブル |
| `db/migrate/20260305110045_create_financial_metrics.rb` | financial_metricsテーブル |
| `db/migrate/20260305110046_create_daily_quotes.rb` | daily_quotesテーブル |
| `db/migrate/20260305110047_create_application_properties.rb` | application_propertiesテーブル |
| `app/models/company.rb` | 企業モデル |
| `app/models/financial_report.rb` | 決算報告書モデル |
| `app/models/financial_value.rb` | 財務数値モデル |
| `app/models/financial_metric.rb` | 分析指標モデル |
| `app/models/daily_quote.rb` | 株価モデル |
| `app/models/application_property.rb` | アプリメタデータモデル |
| `spec/models/concerns/json_attribute_spec.rb` | JsonAttributeテスト |

## 2026-03-05 PLAN: EDINET APIクライアント設計

### 作業概要

EDINET API v2の仕様を詳細調査し、APIクライアント（`EdinetApi`）およびXBRLパーサー（`EdinetXbrlParser`）の詳細設計書を作成した。

### 調査内容

- **EDINET API v2仕様**: ベースURL、認証方式（クエリパラメータ `Subscription-Key`）、書類一覧API（`GET /api/v2/documents.json`）のリクエストパラメータ・レスポンス全29フィールド、書類取得API（`GET /api/v2/documents/{docID}`）のtype=1〜5の取得形式、ZIPファイル内部構造
- **docTypeCode一覧**: 有価証券報告書(120)、訂正有価証券報告書(130)、四半期報告書(140)、訂正四半期報告書(150)、半期報告書(160)、訂正半期報告書(170)を対象書類として選定。決算短信はEDINETでなくTDnet管轄のため対象外
- **レート制限**: 書類一覧APIは1分に1回以下、書類取得APIは3〜5秒間隔が推奨。超過時429エラーまたは一時BAN
- **XBRL構造**: jppfs_cor名前空間（日本基準）のP/L・B/S・C/F主要要素名、jpigp_cor（IFRS）の差異、コンテキストID（CurrentYearDuration / CurrentYearInstant / NonConsolidatedMember等）による期間・連結/個別の区別
- **Ruby XBRL gem状況**: litexbrl（TDnetのみ対応、2016年頃停止）、xbrlware-ce（2010年停止）などいずれも古くメンテナンス停止 → Nokogiriによる自前実装を採用

### 設計判断

- **EdinetApi**: コーディング規約「汎用性と利便性」に従い、`api_key` を引数で受け取り `EdinetApi.default` でcredentialsから取得する便利メソッドを提供。Faraday + faraday-retry でHTTPクライアント実装。エラーハンドリング規約に従い例外は捕捉せず呼び出し元に委ねる
- **EdinetXbrlParser**: Nokogiriベースの自前XBRL パーサー。要素名の候補配列で企業ごとの勘定科目差異に対応（例: NetSales / OperatingRevenue1）。コンテキストIDの正規表現マッチで連結/個別を分離
- **rubyzip gem追加**: ZIPファイル展開用。Gemfileへの追加が必要
- **EPS/BPS等のXBRL直接抽出は将来拡張**: 経営指標セクション（jpcrp_cor）に記載されることが多く、JQUANTS APIからの取得をメインとする方針

### 成果物

| ファイル | 内容 |
|---------|------|
| `todo/20260305_1020_dev_edinet_api_client_DEVELOP_pending.md` | EDINET APIクライアント・XBRLパーサーの詳細実装仕様書（DEVELOP TODO） |
| `todo/20260305_1002_plan_edinet_api_client_PLAN_done.md` | 元PLANのステータスをdoneに変更 |

### 設計したクラス一覧

| クラス名 | 配置先 | 概要 |
|---------|--------|------|
| EdinetApi | app/lib/edinet_api.rb | EDINET API v2 HTTPクライアント。書類一覧取得・XBRL/CSVダウンロード |
| EdinetXbrlParser | app/lib/edinet_xbrl_parser.rb | XBRLパーサー。ZIP展開→Nokogiriパース→財務数値抽出 |

## 2026-03-05 PLAN: データベース設計

### 作業概要

データベーススキーマの詳細設計をおこなった。EDINET API v2 / JQUANTS API v2 の仕様を調査し、取得可能なデータフィールドを把握した上で、マスターデータ層・分析指標層・アプリケーション管理層の3層構成でスキーマを設計した。

### 調査内容

- **EDINET API v2**: 書類一覧API（29フィールド）、書類取得API（XBRL/CSV/PDF）、docTypeCode一覧、XBRL要素名（jppfs_cor名前空間のP/L・B/S・C/F項目）、EDINETコード形式（E+5桁数字）、レート制限（書類一覧1分1回、書類取得3-5秒間隔）
- **JQUANTS API v2**: 上場銘柄一覧、株価四本値、財務情報サマリー（100超フィールド）、決算発表予定日。V2 APIはx-api-keyヘッダー方式。証券コード5桁。プラン別レート制限（Free: 5req/min 〜 Premium: 500req/min）

### 設計判断

- **financial_values**: 固定カラム（主要16項目）+ JSON（拡張データ）のハイブリッド構造を採用。ユースケースで頻繁に検索・比較される値は固定カラムでインデックスの恩恵を受ける。EAVは同一行の複数カラム参照が必要なユースケースに不利と判断
- **financial_metrics**: CLAUDE.md要件に従いマスターテーブルとは別テーブルで管理。連続増収増益期数のインデックスで高速検索を実現
- **daily_quotes**: バリュエーション指標算出に必要な株価データテーブルを追加
- **JsonAttribute concern**: JSON型カラムにスキーマを適用するconcernを設計

### 成果物

| ファイル | 内容 |
|---------|------|
| `todo/20260305_1010_dev_database_schema_DEVELOP_pending.md` | DB実装の詳細仕様書（DEVELOP TODO） |
| `todo/20260305_1001_plan_database_design_PLAN_done.md` | 元PLANのステータスをdoneに変更 |

### 設計したテーブル一覧

| テーブル名 | 層 | 概要 |
|-----------|-----|------|
| companies | マスター | 企業マスター（EDINETコード・証券コード両対応） |
| financial_reports | マスター | 決算報告書メタデータ（EDINET/JQUANTS共通） |
| financial_values | マスター | 財務数値（固定16カラム + JSON拡張） |
| financial_metrics | 分析指標 | 派生指標（YoY成長率・収益性・CF・連続指標） |
| daily_quotes | マスター | 株価四本値（バリュエーション指標算出用） |
| application_properties | アプリ管理 | アプリ全体のメタデータ管理 |

## 2026-03-05 DEVELOP: RSpec導入・テスト基盤構築

### 作業概要

テスティング規約で指定されている RSpec を導入し、テスト基盤を整備した。

### 実施内容

1. Gemfileに `rspec-rails` を追加し `bundle install` を実行
2. `rails generate rspec:install` で初期ファイル（`.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`）を生成
3. `spec/rails_helper.rb` の設定を調整
   - `spec/support/` 配下の自動読み込みを有効化
   - `infer_spec_type_from_file_location!` を有効化
4. `spec/support/.keep` を作成
5. minitest用の `test/` ディレクトリを削除
6. CI（`.github/workflows/ci.yml`）のテスト実行コマンドを `bin/rails test` から `bundle exec rspec` に変更
7. `bundle exec rspec` の正常動作を確認（0 examples, 0 failures）

## 2026-03-05 THINK: プロジェクト初期TODO作成

### 作業概要

プロジェクトの現状を調査し、開発を前進させるために必要なTODOを洗い出して作成した。

### 現状分析

- Railsアプリケーションの基本スケルトンのみが存在する初期段階
- データベーススキーマ未作成、モデル未実装、APIクライアント未実装
- テストフレームワークが minitest（テスティング規約ではRSpec指定）
- Faraday は Gemfile に導入済み

### 作成したTODO

| ファイル | 種別 | 内容 |
|---------|------|------|
| `20260305_1000_dev_rspec_setup_DEVELOP_pending.md` | DEVELOP | RSpec導入・テスト基盤構築 |
| `20260305_1001_plan_database_design_PLAN_pending.md` | PLAN | データベース設計（企業マスター・決算データ・分析指標） |
| `20260305_1002_plan_edinet_api_client_PLAN_pending.md` | PLAN | EDINET APIクライアント設計 |
| `20260305_1003_plan_jquants_api_client_PLAN_pending.md` | PLAN | JQUANTS APIクライアント設計 |
| `20260305_1004_plan_data_import_pipeline_PLAN_pending.md` | PLAN | データ取り込みパイプライン設計 |

### 推奨される作業順序

1. **RSpec導入**（DEVELOP） - テスト基盤がないと他の実装のテストができない
2. **データベース設計**（PLAN） - 全ての実装の基盤となるスキーマ設計
3. **EDINET APIクライアント設計**（PLAN） - 主要データソースの設計
4. **JQUANTS APIクライアント設計**（PLAN） - 補完データソースの設計
5. **データ取り込みパイプライン設計**（PLAN） - DB設計・APIクライアント設計に依存
