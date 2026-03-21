# DEVELOP: モデルのサマリー表示メソッド追加

## 概要

Company, FinancialValue, FinancialMetric に人間が読みやすいサマリーテキストを生成するメソッドを追加し、Railsコンソールでの分析作業やRakeタスク出力の基盤とする。

## 背景・動機

- 現在Railsコンソールでレコードを確認する場合、ActiveRecordのデフォルト `#inspect` が使われ、data_jsonを含む長大な文字列が出力される
- 分析作業において「この企業の直近決算の概要」を素早く把握したいが、必要な情報を抽出するには複数のメソッド呼び出しが必要
- Rakeタスク（pipeline:status等）やスクリーニング結果のCLI出力、将来のWeb UIでも同様のサマリー情報が必要になる
- 既存TODO「dev_screening_result_table_formatter」はスクリーニング結果の一覧表示に特化しており、個別レコードのサマリー表示は対象外
- 既存TODO「dev_company_financial_timeline_viewer」は時系列の可視化であり、単一レコードの概要表示とは異なる

## 実装方針

### Company#summary_text

```ruby
class Company < ApplicationRecord
  # 企業の概要をテキストで返す
  #
  # 出力例:
  #   "7203 トヨタ自動車(株) [輸送用機器] プライム"
  #
  def summary_text
    parts = [securities_code, name]
    parts << "[#{sector_33_name}]" if sector_33_name.present?
    parts << market_name if market_name.present?
    parts.join(" ")
  end
end
```

### FinancialValue#summary_text

```ruby
class FinancialValue < ApplicationRecord
  # 財務数値のサマリーをテキストで返す
  #
  # 出力例:
  #   "FY2025.03 連結 年次 | 売上 3,000,000百万 営業利益 300,000百万 純利益 200,000百万 | EPS 150.5 BPS 2,340.0 自己資本比率 45.2%"
  #
  def summary_text
    period_label = "FY#{fiscal_year_end&.strftime('%Y.%m')}"
    scope_label = scope == "consolidated" ? "連結" : "個別"
    type_label = { "annual" => "年次", "q1" => "Q1", "q2" => "Q2", "q3" => "Q3" }[period_type] || period_type

    header = "#{period_label} #{scope_label} #{type_label}"

    pl_parts = []
    pl_parts << "売上 #{format_amount(net_sales)}" if net_sales
    pl_parts << "営業利益 #{format_amount(operating_income)}" if operating_income
    pl_parts << "純利益 #{format_amount(net_income)}" if net_income

    per_share_parts = []
    per_share_parts << "EPS #{format_decimal(eps)}" if eps
    per_share_parts << "BPS #{format_decimal(bps)}" if bps
    per_share_parts << "自己資本比率 #{format_percent(equity_ratio)}" if equity_ratio

    [header, pl_parts.join(" "), per_share_parts.join(" ")].reject(&:empty?).join(" | ")
  end

  private

  # 金額を百万円単位で表示
  def format_amount(value)
    return nil unless value
    if value.abs >= 1_000_000
      "#{(value / 1_000_000.0).round(0).to_i.to_s(:delimited)}百万"
    elsif value.abs >= 1_000
      "#{(value / 1_000.0).round(0).to_i.to_s(:delimited)}千"
    else
      value.to_s(:delimited)
    end
  end

  def format_decimal(value)
    return nil unless value
    format("%.1f", value)
  end

  def format_percent(value)
    return nil unless value
    "#{format('%.1f', value)}%"
  end
end
```

### FinancialMetric#summary_text

```ruby
class FinancialMetric < ApplicationRecord
  # 財務指標のサマリーをテキストで返す
  #
  # 出力例:
  #   "FY2025.03 連結 | YoY 売上+12.3% 営業利益+8.5% 純利益+15.2% | ROE 12.5% ROA 6.3% 営業利益率 10.0% | 連続増収 6期 連続増益 4期 | FCF +45,000百万"
  #
  def summary_text
    period_label = "FY#{fiscal_year_end&.strftime('%Y.%m')}"
    scope_label = scope == "consolidated" ? "連結" : "個別"

    header = "#{period_label} #{scope_label}"

    yoy_parts = []
    yoy_parts << "売上#{format_yoy(revenue_yoy)}" if revenue_yoy
    yoy_parts << "営業利益#{format_yoy(operating_income_yoy)}" if operating_income_yoy
    yoy_parts << "純利益#{format_yoy(net_income_yoy)}" if net_income_yoy
    yoy_section = yoy_parts.any? ? "YoY #{yoy_parts.join(' ')}" : nil

    profitability_parts = []
    profitability_parts << "ROE #{format_percent(roe)}" if roe
    profitability_parts << "ROA #{format_percent(roa)}" if roa
    profitability_parts << "営業利益率 #{format_percent(operating_margin)}" if operating_margin

    consecutive_parts = []
    consecutive_parts << "連続増収 #{consecutive_revenue_growth}期" if consecutive_revenue_growth && consecutive_revenue_growth > 0
    consecutive_parts << "連続増益 #{consecutive_profit_growth}期" if consecutive_profit_growth && consecutive_profit_growth > 0

    cf_parts = []
    cf_parts << "FCF #{free_cf && free_cf >= 0 ? '+' : ''}#{format_amount(free_cf)}" if free_cf

    sections = [header, yoy_section, profitability_parts.join(' '), consecutive_parts.join(' '), cf_parts.join(' ')]
    sections.reject { |s| s.nil? || s.empty? }.join(" | ")
  end

  private

  def format_yoy(value)
    return nil unless value
    sign = value >= 0 ? "+" : ""
    "#{sign}#{format('%.1f', value * 100)}%"
  end

  def format_percent(value)
    return nil unless value
    "#{format('%.1f', value * 100)}%"
  end

  def format_amount(value)
    return nil unless value
    if value.abs >= 1_000_000
      "#{(value / 1_000_000.0).round(0).to_i.to_s(:delimited)}百万"
    else
      value.to_s(:delimited)
    end
  end
end
```

## テスト

### spec/models/company_spec.rb

- `#summary_text`: 全フィールドが存在する場合の出力フォーマット
- `#summary_text`: sector_33_nameがnilの場合にその部分が省略されること

### spec/models/financial_value_spec.rb

- `#summary_text`: 主要な値が含まれる場合のフォーマット
- `#summary_text`: 全値がnilの場合でもエラーにならないこと
- `#format_amount`: 百万円単位での表示

### spec/models/financial_metric_spec.rb

- `#summary_text`: YoY・収益性・連続成長が含まれる場合のフォーマット
- `#summary_text`: 連続増収/増益が0の場合にその部分が省略されること
- `#format_yoy`: 正負の符号付きパーセンテージ表示

## 依存関係

- 既存のモデルへの純粋な追加（破壊的変更なし）
- Rakeタスク系TODO（pipeline:status等）、スクリーニング結果フォーマッター、Railsコンソール分析の全てで利用可能
- Company検索（dev_company_search_and_lookup）と組み合わせることで、コンソールでの分析ワークフローが大幅に改善
