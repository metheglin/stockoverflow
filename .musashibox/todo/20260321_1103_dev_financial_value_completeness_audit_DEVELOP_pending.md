# DEVELOP: 財務データの項目充足率監査

## 概要

financial_values テーブルの各レコードについて、主要フィールドの充足状況（NULL率）を監査し、メトリクス計算の信頼性に影響するデータ欠損を可視化する。

## 背景・動機

CalculateFinancialMetricsJob は financial_values のカラム値を使って各種メトリクスを計算するが、ソースデータ（JQUANTS / EDINET）によって取得できるフィールドにばらつきがある:

- JQUANTSは主要P/Lデータ（売上・利益）は充実しているが、B/SやC/Fのデータが欠けることがある
- EDINETのXBRLパーサーは要素名のマッピングが完全でない場合があり、NULLになるフィールドがある
- scope（連結/単体）やperiod_type（年次/四半期）によってデータの充足率が大きく異なる

データが欠損していると:
- ROE/ROAが計算できない（net_assets, total_assets がNULL）
- キャッシュフロー指標が計算できない（operating_cf, investing_cf がNULL）
- バリュエーション指標が不正確（EPS, BPS がNULL）
- スクリーニング結果から正常な企業が漏れる

DataIntegrityCheckJob は「メトリクスの欠損」「日次株価の欠損」「連続成長の異常値」をチェックするが、**元データであるfinancial_valuesのフィールドレベルの充足率**はチェックしていない。

## 実装方針

### 監査対象フィールド

優先度の高い順にグループ化:

**必須（P/L基本）**: net_sales, operating_income, ordinary_income, net_income, eps
**重要（B/S）**: total_assets, net_assets, equity_ratio, bps
**重要（C/F）**: operating_cf, investing_cf, financing_cf, cash_and_equivalents
**補助**: shares_outstanding, dividend_per_share

### 配置先

`app/models/financial_value/completeness_audit.rb`

### インターフェース

```ruby
class FinancialValue::CompletenessAudit
  def initialize(scope_type: :consolidated, period_type: :annual)
    @scope_type = scope_type
    @period_type = period_type
  end

  # 全体のフィールド充足率サマリを返す
  def execute
    # { field_name => { total: N, filled: N, null: N, fill_rate: Float }, ... }
  end

  # 特定企業の充足率を返す
  def get_company_completeness(company_id)
    # { field_name => { filled: true/false, value: ... }, ... }
  end

  # 充足率が閾値未満のフィールドを返す
  def get_low_coverage_fields(threshold: 0.5)
    # [{ field: :operating_cf, fill_rate: 0.32 }, ...]
  end

  # メトリクス計算に必要なフィールドが揃っている企業数を返す
  def get_calculable_company_count
    # { growth: N, profitability: N, cf: N, valuation: N }
  end
end
```

### DataIntegrityCheckJob との連携

- DataIntegrityCheckJob にフィールド充足率チェックを追加するオプションを検討
- または独立した監査として、Rakeタスクから実行可能にする

## テスト

- `execute` メソッドが全フィールドの充足率を正しく集計すること（テスト用のFinancialValueインスタンスで検証）
- `get_low_coverage_fields` が閾値に基づいて正しくフィルタすること
- `get_calculable_company_count` が各指標カテゴリの計算可能件数を正しく返すこと
