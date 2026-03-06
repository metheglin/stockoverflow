# Work Log

Claude's development work log for this project.

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
