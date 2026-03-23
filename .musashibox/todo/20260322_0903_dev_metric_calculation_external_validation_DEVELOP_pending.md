# dev_metric_calculation_external_validation

## 概要

自システムで計算した財務指標（ROE, PER, PBR, 営業利益率等）を外部公開データと突合し、計算ロジックの正確性を検証する仕組みを実装する。

## 背景・目的

FinancialMetric のメトリクス計算は CalculateFinancialMetricsJob で実行され、テストも存在するが、**テストは計算ロジックの単体テストであり、実際のデータに対する計算結果が正しいことは検証していない**。

例えば：
- ROE = net_income / net_assets と計算しているが、実際の企業データにおいて外部ソースが公開するROEと一致するか未検証
- PER = close_price / eps と計算しているが、EPSの定義（希薄化後EPS vs 基本EPS）の違いにより差異が生じる可能性
- 連結 vs 非連結の混在、会計基準（日本基準 / IFRS / 米国基準）の違いによる影響

既存の関連TODO:
- `cross_source_data_validation` は「EDINET vs JQUANTSの**生データ**の比較」→ インプットデータの突合
- `financial_statement_balance_validation` は「会計的等式の検証」→ 内部整合性の検証
- 本TODOは「**計算された指標**を外部公開値と比較」→ アウトプットの正確性検証

## 実装内容

### JQUANTSの計算済み指標の活用

JQUANTS の financial_statements エンドポイントは一部の計算済み指標を含む可能性がある。これらを利用して突合する。

### FinancialMetric にバリデーションメソッドを追加

```ruby
class FinancialMetric < ApplicationRecord
  # 外部参照値との差分を検出
  # @param reference [Hash] 外部ソースの指標値 { roe: 0.12, per: 15.3, ... }
  # @param tolerance [Float] 許容誤差率（デフォルト5%）
  # @return [Array<Hash>] 差異のある指標リスト
  def get_deviations_from_reference(reference, tolerance: 0.05)
    deviations = []
    reference.each do |metric_name, ref_value|
      next if ref_value.nil?
      own_value = respond_to?(metric_name) ? send(metric_name) : data_json_value(metric_name)
      next if own_value.nil?
      deviation_rate = (own_value - ref_value).abs / ref_value.abs
      if deviation_rate > tolerance
        deviations << {
          metric: metric_name,
          own_value: own_value,
          reference_value: ref_value,
          deviation_rate: deviation_rate,
        }
      end
    end
    deviations
  end
end
```

### 検証Job

```ruby
class ValidateMetricAccuracyJob < ApplicationJob
  # サンプリングによる検証（全企業ではなく代表的な企業群）
  # - 時価総額上位N社
  # - 各セクターから数社
  # - 会計基準が異なる企業（IFRS適用企業を含む）
  def perform(sample_size: 50)
    # 1. サンプル企業を選定
    # 2. 外部参照値を取得（JQUANTSの計算済み値等）
    # 3. 自システムの計算結果と突合
    # 4. 差異をレポートし ApplicationProperty に記録
  end
end
```

### 差異レポート

ApplicationProperty (kind: :metric_validation) に以下を記録:
- 検証日時
- サンプル数
- 差異が見つかった企業・指標のリスト
- 差異の統計（平均偏差率、最大偏差率）

## テスト方針

- FinancialMetric#get_deviations_from_reference のテスト（一致ケース、許容範囲内、許容範囲超過）
- ValidateMetricAccuracyJob のメソッドテスト（Job実行テストは不要）

## 依存関係

- JQUANTSのレスポンスに計算済み指標が含まれるか要確認
- FinancialMetric の既存計算ロジックが前提

## 優先度

Phase 1。計算ロジックの信頼性を担保するため、analysis_query_layer で本格的なスクリーニングを開始する前に実施が望ましい。特にROE, PER, 営業利益率は3つのユースケースすべてに影響する基本指標。
