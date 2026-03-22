# DEVELOP: DailyQuote後追いインポート時のバリュエーション指標欠損修正

## 概要

`CalculateFinancialMetricsJob` は `FinancialValue` の存在をトリガーとしてバリュエーション指標（PER, PBR, PSR, EV/EBITDA）を算出する。しかし、DailyQuote（株価データ）が未インポートの状態でメトリクスが算出された場合、バリュエーション指標は nil のまま永久に更新されない。

## 問題の詳細

### 原因コード

```ruby
# CalculateFinancialMetricsJob#build_target_scope (行22-34)
def build_target_scope(recalculate:, company_id:)
  scope = FinancialValue.all
  # ...
  if recalculate
    scope
  else
    scope.left_joins(:financial_metric)
         .where(
           "financial_metrics.id IS NULL OR financial_values.updated_at > financial_metrics.updated_at"
         )
  end
end
```

### 問題のシナリオ

1. `ImportJquantsFinancialDataJob` を実行 → FinancialValue が作成される
2. `CalculateFinancialMetricsJob` を実行 → FinancialMetric が作成される
   - この時点で DailyQuote がないため `load_stock_price` は nil を返す
   - バリュエーション指標（PER/PBR/PSR/EV-EBITDA/dividend_yield）は全て nil
3. `ImportDailyQuotesJob` を実行 → DailyQuote が作成される
4. **再度 `CalculateFinancialMetricsJob` を実行しても、FinancialValue.updated_at は変わっていないため、対象外**
5. バリュエーション指標は永久に nil のまま

### 影響

- 初回セットアップ時のインポート順序次第で、全企業のバリュエーション指標が欠損
- 日次運用でも、株価データの取得が遅延した場合に同様の問題が発生
- `recalculate: true` で全再計算すれば修復可能だが、手動介入が必要

## 修正方針

### 案A: バリュエーション指標が nil のメトリクスも再計算対象に含める

```ruby
def build_target_scope(recalculate:, company_id:)
  scope = FinancialValue.all
  scope = scope.where(company_id: company_id) if company_id

  if recalculate
    scope
  else
    scope.left_joins(:financial_metric)
         .where(
           "financial_metrics.id IS NULL " \
           "OR financial_values.updated_at > financial_metrics.updated_at " \
           "OR (financial_metrics.data_json IS NULL OR financial_metrics.data_json = '{}' OR financial_metrics.data_json = '')"
         )
  end
end
```

- 利点: 既存のジョブ実行フローに自然に統合される
- 欠点: data_json が空の理由がバリュエーション未算出なのか、単にデータがないのかを区別できない。不要な再計算が走る可能性

### 案B: バリュエーション指標のみ後から補完するメソッドを追加

```ruby
# CalculateFinancialMetricsJob に追加
def perform(recalculate: false, company_id: nil, fill_valuations: false)
  if fill_valuations
    fill_missing_valuations(company_id: company_id)
  else
    # 既存ロジック
  end
end

def fill_missing_valuations(company_id: nil)
  # data_json にバリュエーション指標がないメトリクスを対象
  # 対応する DailyQuote が存在する場合のみ再算出
  scope = FinancialMetric.all
  scope = scope.where(company_id: company_id) if company_id

  scope.find_each do |metric|
    next if metric.per.present? || metric.pbr.present?

    stock_price = load_stock_price(metric.financial_value)
    next unless stock_price

    valuation = FinancialMetric.get_valuation_metrics(metric.financial_value, stock_price)
    ev_ebitda = FinancialMetric.get_ev_ebitda(metric.financial_value, stock_price)

    json_updates = valuation.merge(ev_ebitda)
    next if json_updates.empty?

    metric.data_json = (metric.data_json || {}).merge(json_updates)
    metric.save!
  end
end
```

- 利点: 対象が明確で不要な再計算が発生しない
- 欠点: ジョブの呼び出しパラメータが増える

### 推奨: 案B

バリュエーション補完を独立したオプションとして提供する。パイプラインのRakeタスクで `ImportDailyQuotesJob` の後に `CalculateFinancialMetricsJob.perform_now(fill_valuations: true)` を実行する運用とする。

## テスト

- `fill_missing_valuations`: DailyQuote存在時にバリュエーション指標が補完されること
- `fill_missing_valuations`: 既にバリュエーション指標がある場合はスキップされること
- `fill_missing_valuations`: DailyQuoteがない場合はスキップされること

## 関連TODO

- `20260322_1800_bugfix_valuation_split_adjustment_mismatch` - 株価の分割調整と合わせて修正する
- `20260321_0903_dev_rake_task_pipeline_operations` - パイプライン実行順序の中に本修正を組み込む
