# DEVELOP: CalculateFinancialMetricsJob の処理順序バグ修正

## 概要

`CalculateFinancialMetricsJob` の `find_each` による処理順序が `id` 順であるため、同一企業の複数期の FinancialValue が fiscal_year_end の昇順で処理されない場合がある。これにより `consecutive_revenue_growth` / `consecutive_profit_growth` の計算が不正確になるバグを修正する。

## 背景・バグ詳細

### 現状のコード

```ruby
target_values.find_each do |fv|
  calculate_metrics_for(fv)
end
```

`find_each` はデフォルトで primary key (id) 順に処理する。`calculate_metrics_for` 内で `find_metric(previous_fv)` を呼び出し、前期の FinancialMetric の `consecutive_revenue_growth` を参照して当期のカウンターを計算している。

### バグの発生条件

1. **recalculate: true の場合**: 全 FinancialValue のメトリクスを再計算するが、id 順で処理するため新しい期が先に処理される可能性がある
2. **一括インポート後の初回計算**: 複数期の FinancialValue が同時にメトリクス未計算の状態で存在する場合
3. **過去データの後追いインポート**: 2024年3月期のデータを後からインポートした場合、id が 2025年3月期より大きくなり、find_each での処理順が逆転する

### 具体例

```
FinancialValue#100: company_id=1, fiscal_year_end=2025-03-31 (先に取り込み)
FinancialValue#200: company_id=1, fiscal_year_end=2024-03-31 (後で取り込み)
```

find_each の処理順: #100 (2025) → #200 (2024)

1. FV#100 (2025) 処理時: previous_fv = FV#200 (2024) を発見。しかし FV#200 のメトリクスはまだ計算されていない → previous_metric = nil → consecutive_revenue_growth = 1 or 0
2. FV#200 (2024) 処理時: 正しく計算される
3. 結果: 2025年のconsecutive_growthが不正確（前期のカウンターが反映されていない）

## 実装方針

### 処理順序の修正

`find_each` は任意カラムでの ORDER BY をサポートしないため、以下のいずれかの方法で対応する:

#### 案A: 企業ごとにグルーピングして fiscal_year_end 順で処理

```ruby
target_company_ids = target_values.distinct.pluck(:company_id)

target_company_ids.each do |cid|
  target_values
    .where(company_id: cid)
    .order(:fiscal_year_end)
    .each { |fv| calculate_metrics_for(fv) }
end
```

#### 案B: find_in_batches + ソート

```ruby
target_values.find_in_batches(batch_size: 1000) do |batch|
  batch.sort_by(&:fiscal_year_end).each do |fv|
    calculate_metrics_for(fv)
  end
end
```

### 推奨: 案A

- 企業ごとに処理することで、連続成長カウンターの依存チェーンが確実に正しい順序で処理される
- メモリ効率も良好（1企業分のクエリは数十件程度）
- company_id + fiscal_year_end のインデックスは既存のユニーク制約で対応済み

## テスト

`spec/jobs/calculate_financial_metrics_job_spec.rb` に以下のテストを追加:

- 同一企業の3期分のFinancialValueがid逆順で存在する場合に、consecutive_revenue_growthが正しく累積されること
- recalculate: true で全再計算した結果が、id順序に依存しないこと

## 影響範囲

- `app/jobs/calculate_financial_metrics_job.rb`
- `spec/jobs/calculate_financial_metrics_job_spec.rb`（新規）

## 優先度

高。データの正確性に直結するバグ。recalculate: true で全再計算するケースだけでなく、日常的な増分計算でもデータ投入順序によって発生しうる。

## 依存関係

- なし（既存ジョブの修正のみ）
- `dev_remaining_job_method_tests` (20260321_1400) と並行して実施可能
