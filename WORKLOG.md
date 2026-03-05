# Work Log

Claude's development work log for this project.

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
