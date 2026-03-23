# PLAN: 対話型分析コンソールの設計

## 概要

Railsコンソール（`rails c`）に代わる、財務分析の作業フローに特化した対話型コンソールインターフェースを設計する。

## 背景・動機

現在、蓄積されたデータを分析するには `rails console` を起動し、ActiveRecordのクエリを直接記述する必要がある:

```ruby
# 6期連続増収増益企業を探したいとき
FinancialMetric.where("consecutive_revenue_growth >= ?", 6)
  .where("consecutive_profit_growth >= ?", 6)
  .joins(:company).where(companies: { listed: true })
  .order(revenue_yoy: :desc)
  .each { |m| puts "#{m.company.name}: #{m.revenue_yoy}" }
```

この方式には以下の課題がある:

- ActiveRecordの構文知識が必要で、分析に集中できない
- よく使うクエリパターンを毎回組み立てる非効率
- 出力が整形されておらず、結果の読み取りが困難
- 分析の「ワークフロー」（検索→詳細→比較）を効率的に進められない
- Rakeタスク（TODO: dev_rake_operations_tasks）は個別コマンドの実行であり、対話的な探索には向かない

### 既存TODOとの関係

- `dev_rake_operations_tasks` / `dev_rake_task_pipeline_operations`: パイプラインの実行・ステータス確認用。分析用途ではない
- `dev_data_export_cli`: データエクスポート機能。出力先が異なる
- `dev_screening_result_table_formatter`: スクリーニング結果の整形。本TODOの一部として活用可能
- `plan_web_dashboard`: 将来のWebインターフェース。本TODOはWeb UI前の暫定的な分析手段

## 設計してほしい内容

### 1. インターフェース設計

- Rakeタスクとして実装するか、独立したコマンドラインツールとするか
- REPL的な対話モードか、サブコマンド方式か
- 入力・出力のフォーマット設計

### 2. 分析ワークフロー

本プロジェクトの3つの主要ユースケースをカバーする操作フロー:

#### ユースケース1: 条件スクリーニング
「6期連続増収増益企業を増収率順に表示」のような条件を簡潔に指定し、結果を一覧表示する

#### ユースケース2: 条件の組み合わせ + 状態変化の検出
「営業CF+/投資CF-の企業のうち、FCFがプラスに転換した企業」のような複合条件 + 変化検出

#### ユースケース3: 企業深掘り
スクリーニング結果から気になった企業を選び、その企業の全期間の業績推移を確認する

### 3. コマンド体系の設計

具体的なコマンド名・引数・オプションの設計。以下は例:

```
# スクリーニング
screen --revenue-growth-consecutive>=6 --profit-growth-consecutive>=6 --sort=revenue_yoy:desc

# 企業検索
find トヨタ
find 7203

# 企業詳細
show 7203
show 7203 --timeline --years=7

# 比較
compare 7203 6758 --metrics=roe,roa,operating_margin
```

### 4. 出力整形

- ターミナルでの表形式出力
- 数値のフォーマット（百万円単位、パーセント、小数点桁数）
- カラー表示の活用（増収=緑、減収=赤など）

### 5. 技術選定

- Ruby製CLIフレームワーク（Thor, TTY toolkit等）の利用検討
- ターミナルテーブル表示（terminal-table gem等）の利用検討
- Railsアプリケーションとの統合方法

## 成果物

- インターフェース設計書
- コマンド体系の仕様
- 技術選定の根拠
- 実装フェーズの分割提案（Phase 1: 基本検索/表示、Phase 2: スクリーニング、Phase 3: 比較/エクスポート）
- 実装用のDEVELOP TODOファイル

## 依存関係

- `dev_company_search_and_lookup` の検索メソッドを活用
- `dev_company_financial_timeline_view` のタイムライン表示ロジックを活用
- `dev_screening_result_table_formatter` の整形ロジックを活用
- `dev_analysis_query_layer` のQueryObjectsを活用
