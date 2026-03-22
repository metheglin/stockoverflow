# DEVELOP: 企業別データカバレッジ評価

## 概要

スクリーニング結果の信頼性を担保するため、各企業が保持するデータの網羅性・完全性を評価する仕組みを構築する。データカバレッジが不十分な企業をスクリーニングから除外したり、結果に信頼度を付加したりするための基盤となる。

## 背景・動機

現在のスクリーニングは、データが存在する企業を一律に比較対象としている。しかし実際には:

- ある企業は10期分のデータがあるが、別の企業は2期分しかない
- CF（キャッシュフロー）データがない企業が存在する（JQUANTSの一部期間はCFデータ未提供）
- 株価データがない期間がある（非上場化、売買停止など）
- 個別のみ報告の企業はdata_json内の拡張データ（XBRL由来）がない場合がある

「6期連続増収増益」をスクリーニングする際、5期分のデータしかない企業のconsecutive_revenue_growthが5であっても、6期以上の企業と同列に比較するのは不公平。

## 実装内容

### 1. Company にデータカバレッジ評価メソッドを追加

```ruby
# app/models/company.rb

# 企業のデータカバレッジを評価する
#
# @param scope_type [Symbol] :consolidated or :non_consolidated
# @param period_type [Symbol] :annual（デフォルト）
# @return [Hash] カバレッジ情報
#
# 返却例:
#   {
#     total_periods: 8,           # 通期データの総数
#     earliest_fiscal_year_end: Date.new(2017, 3, 31),
#     latest_fiscal_year_end: Date.new(2024, 3, 31),
#     has_cf_data: true,          # CF計算書データの有無
#     has_stock_price: true,      # 株価データの有無
#     has_xbrl_extended: true,    # XBRL拡張データ（原価・販管費等）の有無
#     has_forecast_data: true,    # 業績予想データの有無
#     metric_periods: 7,          # メトリクス算出済み期数
#     valuation_periods: 5,       # バリュエーション指標が算出済みの期数
#     coverage_score: 0.85,       # 総合カバレッジスコア（0.0〜1.0）
#   }
#
def get_data_coverage(scope_type: :consolidated, period_type: :annual)
  fvs = financial_values.where(scope: scope_type, period_type: period_type)
  fms = financial_metrics.where(scope: scope_type, period_type: period_type)

  fv_list = fvs.order(fiscal_year_end: :asc).to_a
  fm_list = fms.to_a

  return empty_coverage if fv_list.empty?

  {
    total_periods: fv_list.size,
    earliest_fiscal_year_end: fv_list.first.fiscal_year_end,
    latest_fiscal_year_end: fv_list.last.fiscal_year_end,
    has_cf_data: fv_list.any? { |fv| fv.operating_cf.present? },
    has_stock_price: daily_quotes.exists?,
    has_xbrl_extended: fv_list.any? { |fv| fv.data_json&.key?("cost_of_sales") },
    has_forecast_data: fv_list.any? { |fv| fv.data_json&.key?("forecast_net_sales") },
    metric_periods: fm_list.size,
    valuation_periods: fm_list.count { |fm| fm.per.present? || fm.pbr.present? },
    coverage_score: get_coverage_score(fv_list, fm_list),
  }
end
```

### 2. カバレッジスコアの算出ロジック

```ruby
# カバレッジスコアを0.0〜1.0で算出する
#
# 評価要素（各0.0〜1.0、均等加重）:
# - 期数の十分さ: 8期以上で1.0（分析に十分な期間）
# - メトリクス算出率: metric_periods / total_periods
# - CF データ保有率: CFデータがある期数 / total_periods
# - バリュエーション算出率: valuation_periods / metric_periods
#
# @return [Float] 0.0〜1.0
def get_coverage_score(fv_list, fm_list)
  return 0.0 if fv_list.empty?

  period_score = [fv_list.size / 8.0, 1.0].min
  metric_ratio = fm_list.size.to_f / fv_list.size
  cf_ratio = fv_list.count { |fv| fv.operating_cf.present? }.to_f / fv_list.size
  val_ratio = if fm_list.any?
                fm_list.count { |fm| fm.per.present? || fm.pbr.present? }.to_f / fm_list.size
              else
                0.0
              end

  ((period_score + metric_ratio + cf_ratio + val_ratio) / 4.0).round(4)
end
```

### 3. スクリーニングでの活用

`Company::ScreeningQuery` に `min_coverage_score` オプションを追加:

```ruby
# Company::ScreeningQuery 修正案
# @param min_coverage_score [Float, nil] 最低カバレッジスコア（0.0〜1.0）
# @param min_periods [Integer, nil] 最低期数
```

スクリーニング結果の各Hashに `coverage_score` を含めることで、ユーザーがデータ信頼度を確認可能にする。

## テスト

### Company#get_data_coverage テスト
- 十分なデータがある企業で正しいカバレッジ情報が返ること
- CFデータがない企業で `has_cf_data: false` が返ること
- データが一切ない企業で `empty_coverage` が返ること

### Company#get_coverage_score テスト
- 8期以上のデータ・全指標算出済みの場合にスコアが1.0に近いこと
- 2期のみ・バリュエーションなしの場合にスコアが低いこと
- 空リストで0.0が返ること

## 注意事項

- `get_data_coverage` はDBクエリを発生させるため、大量の企業に対して一括呼び出しするとN+1問題が発生する。スクリーニング時に使う場合は、先にメトリクスでフィルタしてから対象企業のみに適用すること
- カバレッジスコアの重み付けは、利用経験に基づいて将来的に調整可能な設計とする

## 関連TODO

- `20260312_1000_dev_analysis_query_layer` - スクリーニングQueryObjectに統合する
- `20260319_1503_improve_data_coverage_analysis` - データカバレッジの包括的分析。本TODOは企業単位の評価に特化
