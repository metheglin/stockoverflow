# WORKLOG: WEBダッシュボード Phase 2 - 検索ダッシュボード バックエンド

作業日時: 2026-03-26

元TODO: `todo/20260325_1810_dev_dashboard_phase2_search_backend_DEVELOP_done.md`

## 作業概要

検索ダッシュボードのバックエンド実装（モデル、条件実行エンジン、コントローラー、ビルトインプリセットseed）を完了した。

## 作業内容

### 1. マイグレーション作成・実行

- `db/migrate/20260326090227_create_screening_presets.rb` を作成
- screening_presets テーブルを作成（name, description, preset_type, conditions_json, display_json, status, execution_count, last_executed_at）
- preset_type と status にインデックスを付与

### 2. ScreeningPreset モデル実装

- `app/models/screening_preset.rb` を作成
- enum: preset_type (builtin/custom), status (disabled/enabled)
- JsonAttributeによるdisplay_jsonスキーマ定義（columns, sort_by, sort_order, limit）
- parsed_conditions / parsed_display ヘルパーメソッド
- record_execution! メソッド（execution_count+1 と last_executed_at 更新）

### 3. FinancialMetric に latest_period scope を追加

- サブクエリを使用して各company_id + scope + period_type の組み合わせで最新のfiscal_year_endのみを取得するスコープ
- 既存のインデックス `idx_financial_metrics_timeline` を活用

### 4. ScreeningPreset::ConditionExecutor 実装

- `app/models/screening_preset/condition_executor.rb` に条件実行エンジンを実装
- **SQLレベル条件**: metric_range, metric_boolean, company_attribute
- **ポストフィルタ条件**: data_json_range, metric_top_n, preset_ref
- AND/ORの再帰的ネスト対応
- ホワイトリストによるSQLインジェクション防止
- preset_ref の再帰深さ制限（最大3段）で循環参照を防止
- 非上場企業を自動除外（Company.listed とのjoin）

### 5. テスト作成

- `spec/models/screening_preset/condition_executor_spec.rb` に30テストケースを作成
- build_base_scope: scope_type/period_type適用、非上場除外、最新期間のみ
- apply_conditions: metric_range(min/max)、metric_boolean(true/false)、company_attribute、AND/OR/ネスト
- execute: data_json_range、metric_top_n(asc/desc)、preset_ref、循環参照耐性
- ソート・リミット・ホワイトリスト検証・結果構造テスト

### 6. Dashboard::SearchController 実装

- index: 有効なプリセット一覧をexecution_count降順で取得
- execute: JSON条件を受け取りConditionExecutorで実行、turbo_stream/json対応

### 7. Dashboard::PresetsController 実装

- index: 有効プリセット一覧
- show: プリセット実行 + execution記録
- create: カスタムプリセット作成
- destroy: カスタムプリセットのみ削除可

### 8. ビルトインプリセットseed

- `db/seeds/screening_presets.rb` に6つのビルトインプリセットを定義
  1. 連続増収増益（6期以上）
  2. 高ROE・低PBR バリュー
  3. 高成長グロース
  4. FCF プラス転換
  5. 高配当利回り
  6. 総合スコアTOP100
- `db/seeds.rb` を更新し、seeds/ディレクトリ内のファイルを自動ロード
- 冪等性確認済み

## テスト結果

- 全307テスト合格（0失敗、5 pending=既存のcredentials未設定スキップ）
- 新規追加テスト: 30件（ConditionExecutor）

## 新規作成ファイル

| ファイル | 内容 |
|---------|------|
| `db/migrate/20260326090227_create_screening_presets.rb` | テーブル作成 |
| `app/models/screening_preset.rb` | モデル |
| `app/models/screening_preset/condition_executor.rb` | 条件実行エンジン |
| `db/seeds/screening_presets.rb` | ビルトインプリセット |
| `spec/models/screening_preset/condition_executor_spec.rb` | テスト |

## 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `app/models/financial_metric.rb` | latest_period scope追加 |
| `app/controllers/dashboard/search_controller.rb` | 検索実行ロジック実装 |
| `app/controllers/dashboard/presets_controller.rb` | プリセットCRUDロジック実装 |
| `db/seeds.rb` | seedsディレクトリ自動ロード追加 |

## 設計判断

- data_json内フィールドのフィルタはSQLiteのJSON関数ではなくRubyレベルのポストフィルタで実装した。理由: SQLiteのJSON関数にインデックスが効かず、固定カラムでまず絞り込んだ後にRubyでフィルタする方がパフォーマンス・可読性ともに優位
- ソートはSQLレベルの固定カラムのみ対応。data_jsonフィールドのソートはフロントエンド側で対応を検討
- ルーティングは既にPhase 1で定義済みだったため変更不要
