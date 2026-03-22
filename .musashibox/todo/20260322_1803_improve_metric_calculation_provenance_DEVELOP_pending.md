# DEVELOP: メトリクス計算のプロバナンス（出所・根拠）記録

## 概要

`CalculateFinancialMetricsJob` がメトリクスを算出する際に、計算に使用した入力データの情報（株価、前期データの参照先、計算日時）を `FinancialMetric.data_json` に記録する。メトリクスの正確性を検証・デバッグする際に不可欠な情報。

## 背景

現在の問題:
- あるメトリクスのROEやPERが不正確に見えるとき、何が原因かを特定する手段がない
- バリュエーション指標は株価に依存するが、どの日付のどの株価が使われたか不明
- YoY指標は前期データに依存するが、どの前期レコードが使われたか不明
- 計算ロジックを修正した後、いつ再計算されたレコードかを判別できない

## 実装内容

### 1. `data_json` にプロバナンス情報を追加

`CalculateFinancialMetricsJob#calculate_metrics_for` で、計算に使用した入力情報を記録する。

```ruby
provenance = {
  "calculated_at" => Time.current.iso8601,
  "stock_price_used" => stock_price&.to_f,
  "stock_price_date" => stock_price_date&.iso8601,
  "previous_fv_id" => previous_fv&.id,
  "previous_fv_fiscal_year_end" => previous_fv&.fiscal_year_end&.iso8601,
  "roe_denominator" => roe_denominator_type,  # "shareholders_equity" or "net_assets"
}
```

### 2. `load_stock_price` メソッドの拡張

現在は株価のみを返しているが、株価と日付の両方を返すように変更する。

```ruby
# Before:
def load_stock_price(fv)
  DailyQuote.where(...).pick(:adjusted_close)
end

# After:
def load_stock_price_with_date(fv)
  DailyQuote.where(...).pick(:adjusted_close, :traded_on)
  # => [1500.0, Date.new(2025, 3, 31)]
end
```

### 3. プロバナンスの data_json 格納

既存の valuation/ev_ebitda/surprise と同じ階層で `_provenance` キーに格納する。

```json
{
  "per": 15.2,
  "pbr": 1.8,
  "_provenance": {
    "calculated_at": "2026-03-22T10:00:00+09:00",
    "stock_price_used": 1500.0,
    "stock_price_date": "2025-03-31",
    "previous_fv_id": 12345,
    "previous_fv_fiscal_year_end": "2024-03-31"
  }
}
```

`_` プレフィックスによって通常の指標データと区別する。

## テスト

### `spec/models/financial_metric_spec.rb` への追加は不要

プロバナンスの記録は `CalculateFinancialMetricsJob` 内のロジックであり、テスティング規約に基づきジョブの実行テストは記述しない。`load_stock_price_with_date` は内部メソッドのため、直接テストの対象としない。

## 影響範囲

- `app/jobs/calculate_financial_metrics_job.rb` - `calculate_metrics_for`, `load_stock_price` の拡張
- `app/models/financial_metric.rb` - 変更なし（data_json スキーマ拡張不要、`_provenance` は非スキーマ管理）
