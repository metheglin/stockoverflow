# DEVELOP: CLI分析ヘルパー・データエクスポートツール

## 背景

データ取り込みパイプラインと指標算出が完成しているが、蓄積されたデータを実際に利用する手段がない。Web APIの設計・実装完了を待つまでの間、データを活用する即効性のある手段として、rakeタスクによるCLI分析ツールとCSVエクスポート機能を整備する。

分析クエリレイヤー（plan_analysis_query_layer）の実装後に着手するのが望ましい。クエリレイヤーが定義するscope/QueryObjectを活用してrakeタスクを構築する。

## 前提

- 分析クエリレイヤーの実装が完了していること

## 実装内容

### 1. スクリーニングrakeタスク

CLAUDE.mdの3つのユースケースに対応するrakeタスクを実装する。

```
# ユースケース1: 連続増収増益企業
rake stockoverflow:screen:consecutive_growth[min_periods]
# 例: rake stockoverflow:screen:consecutive_growth[6]
# 出力: 証券コード, 企業名, 連続増収期数, 連続増益期数, 直近増収率

# ユースケース2: フリーCF転換企業
rake stockoverflow:screen:cf_turnaround
# 出力: 証券コード, 企業名, 前期フリーCF, 当期フリーCF, 営業CF, 投資CF

# ユースケース3: 企業の時系列分析
rake stockoverflow:analyze:timeline[securities_code]
# 例: rake stockoverflow:analyze:timeline[72030]
# 出力: 年度, 売上, 営業利益, 純利益, ROE, 各YoY, 連続増収増益期数
```

### 2. CSVエクスポートrakeタスク

分析結果をCSVファイルとして出力する汎用ツール。

```
# 全上場企業の最新指標一覧
rake stockoverflow:export:latest_metrics[output_path]
# 出力カラム: 証券コード, 企業名, 業種, 市場, 売上, 営業利益, 純利益,
#   ROE, ROA, 営業利益率, 各YoY, 連続増収増益期数, PER, PBR, PSR

# 特定企業の財務データ時系列
rake stockoverflow:export:company_timeline[securities_code,output_path]
```

### 3. 実装方針

- `lib/tasks/stockoverflow.rake` にrakeタスクを定義
- 出力は標準出力（TSV形式、ヘッダー付き）を基本とし、`output_path` 指定時のみCSVファイルに出力
- 分析クエリレイヤーのscope/QueryObjectを呼び出す薄いラッパーとして実装
- ページングは不要（CLI出力のため全件出力）

## テスト

- テスティング規約に従い、rakeタスクのテストは記述しない
- 分析ロジック自体はクエリレイヤーのテストでカバーされる前提

## 成果物

- `lib/tasks/stockoverflow.rake` - 分析・エクスポートrakeタスク
