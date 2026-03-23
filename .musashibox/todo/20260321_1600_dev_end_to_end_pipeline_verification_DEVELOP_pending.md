# DEVELOP: パイプライン全体のEnd-to-End動作検証

## 概要

データ収集からメトリクス計算まで、既存パイプラインが正しく連携して動作し、最終的に正しい分析結果が得られることをEnd-to-Endで検証するスクリプトを作成する。

## 背景・動機

- 現在、各ジョブ・モデル・APIクライアントは個別にテストされているが、パイプライン全体を通した統合検証が存在しない
- SyncCompaniesJob → ImportJquantsFinancialDataJob → ImportDailyQuotesJob → CalculateFinancialMetricsJob の連鎖が正しく動作し、FinancialMetricに妥当な値が格納されることを確認する手段がない
- 個別のユニットテストが通っていても、ジョブ間のデータ受け渡し（financial_reportとfinancial_valueの紐付け、financial_valueとfinancial_metricの紐付け）に問題がないことは保証されない
- 既存の `dev_full_pipeline_orchestration`（20260321_1101）はパイプラインの「実行」を担うが、結果の「検証」は対象外
- 既存の `data_integrity_check_job` はデータ整合性のチェックを行うが、パイプライン連携の正当性検証とは異なる

## 実装内容

### 1. 検証用rakeタスク

`lib/tasks/verification.rake` に検証タスクを実装する。

```
rake verify:pipeline[securities_code]
# 例: rake verify:pipeline[72030]  # トヨタ自動車を対象に検証
```

### 2. 検証ステップ

特定の1社（証券コード指定）を対象に以下を順次検証する:

#### Step 1: 企業マスタ確認
- Company レコードが存在し、name, market_code, sector_17_code 等の基本属性が入っていること

#### Step 2: 財務データ連鎖確認
- FinancialReport が1件以上存在すること
- 各 FinancialReport に対応する FinancialValue が存在すること
- FinancialValue の主要カラム（net_sales, operating_income, net_income）がnilでないこと
- 連結・個別の区分が正しく設定されていること

#### Step 3: メトリクス計算確認
- 2期以上の FinancialValue が存在する場合、FinancialMetric が存在すること
- YoY成長率が手計算と一致すること（net_sales_yoy = (当期net_sales - 前期net_sales) / |前期net_sales|）
- ROE, ROA, 営業利益率が手計算と一致すること
- consecutive_revenue_growth, consecutive_profit_growth が論理的に正しいこと

#### Step 4: 株価データ確認
- DailyQuote が存在し、close_price が妥当な範囲（> 0）であること
- PER, PBR 等のバリュエーション指標が計算されている場合、株価データとの整合性を確認

#### Step 5: サマリー出力
- 検証結果を PASS/FAIL でサマリー表示
- FAIL の場合は具体的な不整合内容を表示

### 3. 実装方針

- 検証ロジックは `app/jobs/pipeline_verification_job.rb` に実装し、rakeタスクから呼び出す
- 各ステップの検証メソッドはpublicとし、個別にテスト可能にする
- 検証のためのデータ投入は行わない（既存データに対して検証のみ実施）

## テスト

- 各検証メソッド（`verify_company_master`, `verify_financial_chain`, `verify_metric_calculation` 等）のユニットテスト
- 手計算した期待値との比較ロジックのテスト

## 依存関係

- 既存のジョブが全て実行済みで、データが1社分以上存在すること
- 分析クエリレイヤーには依存しない（生のモデル層で検証するため）
