# メトリクス計算プラグインフレームワーク

## 概要

現在 `CalculateFinancialMetricsJob` に全指標の計算ロジックが集中しており、今後30件以上の指標追加TODOが控えている。
個々の指標をプラグイン的に追加できるフレームワークを構築し、メトリクス計算の拡張性と保守性を確保する。

## 背景・動機

- 既存の `CalculateFinancialMetricsJob` は成長性・収益性・CF・連続成長・バリュエーション・サプライズの計算を1つのジョブ内で実行
- 今後予定されている指標追加（Piotroski F-Score, Altman Z-Score, DuPont分解, ROIC, CAGR, Magic Formula等）を全てこのジョブに追加するとファイルが肥大化し、テストも困難になる
- 各指標計算クラスが統一インターフェースを持つことで、テスト容易性と独立した開発が可能になる

## 実装方針

### 基本インターフェース

```ruby
# app/models/financial_metric/calculator_base.rb
class FinancialMetric::CalculatorBase
  # 計算に必要な入力を受け取る
  def initialize(financial_value:, previous_financial_value: nil, previous_metric: nil, stock_price: nil)
  end

  # 計算結果をHashで返す（financial_metricsのカラムまたはdata_jsonのキーに対応）
  def calculate
    raise NotImplementedError
  end

  # この計算機が実行可能かどうか（必要なデータが揃っているか）
  def calculable?
    raise NotImplementedError
  end

  # 結果の格納先 :column または :data_json
  def storage_type
    :data_json
  end
end
```

### 既存ロジックの移行

- `FinancialMetric.get_growth_metrics` → `FinancialMetric::GrowthCalculator`
- `FinancialMetric.get_profitability_metrics` → `FinancialMetric::ProfitabilityCalculator`
- `FinancialMetric.get_cf_metrics` → `FinancialMetric::CashFlowCalculator`
- `FinancialMetric.get_consecutive_metrics` → `FinancialMetric::ConsecutiveGrowthCalculator`
- `FinancialMetric.get_valuation_metrics` → `FinancialMetric::ValuationCalculator`

### レジストリパターン

```ruby
class FinancialMetric::CalculatorRegistry
  CALCULATORS = [
    FinancialMetric::GrowthCalculator,
    FinancialMetric::ProfitabilityCalculator,
    FinancialMetric::CashFlowCalculator,
    # 新しい計算クラスをここに追加するだけ
  ].freeze
end
```

### CalculateFinancialMetricsJob の改修

レジストリから全計算クラスを取得し、`calculable?` を確認しつつ順次実行する設計にリファクタリング。

## 備考

- 既存のクラスメソッド群は当面残し、新しい Calculator クラスから内部的に呼び出す移行も可
- テストは各 Calculator クラスに対して個別に記述する
