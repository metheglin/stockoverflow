# DEVELOP: XBRL拡張データを活用した FinancialMetric 新指標の実装

## 概要

`dev_xbrl_jppfs_element_expansion` と `dev_xbrl_jpcrp_namespace_support` で追加されたXBRL拡張データを活用し、FinancialMetric に新たな分析指標の算出ロジックを実装する。

## 背景・動機

XBRL要素拡張により FinancialValue の data_json に以下のデータが新たに格納される:

- P/L詳細: 営業外損益、特別損益、法人税、支払利息
- B/S詳細: 有利子負債3要素、運転資本項目（売掛金・棚卸資産・買掛金）、のれん等
- C/F: 減価償却費
- jpcrp_cor: R&D費、設備投資額、従業員数

これらのデータを活用し、以下の3カテゴリの新指標を FinancialMetric に追加する。

## 実装する指標

### カテゴリ1: EBITDA・有利子負債関連指標

FinancialMetric の data_json に追加。

```ruby
# FinancialMetric.get_ebitda_metrics(fv) を新設
# 既存の get_ev_ebitda を置き換え/拡張

def self.get_ebitda_metrics(fv, stock_price)
  result = {}

  depreciation = fv.depreciation_and_amortization
  if depreciation.present? && fv.operating_income.present?
    ebitda = fv.operating_income + depreciation
    result["ebitda"] = ebitda

    # EBITDAマージン
    if fv.net_sales.present? && fv.net_sales > 0
      result["ebitda_margin"] = safe_divide(ebitda, fv.net_sales)&.to_f
    end

    # EV/EBITDA（精緻版）
    if stock_price.present? && fv.shares_outstanding.present?
      market_cap = stock_price * fv.shares_outstanding
      interest_bearing_debt = get_interest_bearing_debt(fv)
      cash = fv.cash_and_equivalents || 0
      ev = market_cap + (interest_bearing_debt || 0) - cash
      result["ev_ebitda"] = safe_divide(ev, ebitda)&.to_f if ebitda > 0
    end
  end

  result
end

# 有利子負債の正確な算出
def self.get_interest_bearing_debt(fv)
  short = fv.short_term_loans_payable
  long = fv.long_term_loans_payable
  bonds = fv.bonds_payable

  return nil if [short, long, bonds].all?(&:nil?)
  (short || 0) + (long || 0) + (bonds || 0)
end
```

**data_json 追加キー:**
- `ebitda` (integer) - 営業利益 + 減価償却費
- `ebitda_margin` (decimal) - EBITDA / 売上高
- `interest_bearing_debt` (integer) - 有利子負債合計
- `net_debt` (integer) - 有利子負債 - 現預金
- `debt_to_ebitda` (decimal) - 有利子負債 / EBITDA（返済能力）
- `interest_coverage_ratio` (decimal) - 営業利益 / 支払利息（利息支払能力）

### カテゴリ2: 運転資本・CCC（キャッシュ・コンバージョン・サイクル）

```ruby
# FinancialMetric.get_working_capital_metrics(fv) を新設

def self.get_working_capital_metrics(fv)
  result = {}
  return result unless fv.net_sales.present? && fv.net_sales > 0

  daily_sales = fv.net_sales.to_d / 365

  # 売上債権回転日数
  if fv.notes_and_accounts_receivable.present?
    result["receivable_turnover_days"] = safe_divide(fv.notes_and_accounts_receivable, daily_sales)&.to_f
  end

  # 棚卸資産回転日数（売上原価ベース）
  cost = fv.cost_of_sales
  if fv.inventories.present? && cost.present? && cost > 0
    daily_cost = cost.to_d / 365
    result["inventory_turnover_days"] = safe_divide(fv.inventories, daily_cost)&.to_f
  end

  # 仕入債務回転日数
  if fv.notes_and_accounts_payable.present? && cost.present? && cost > 0
    daily_cost = cost.to_d / 365
    result["payable_turnover_days"] = safe_divide(fv.notes_and_accounts_payable, daily_cost)&.to_f
  end

  # CCC（キャッシュ・コンバージョン・サイクル）
  recv = result["receivable_turnover_days"]
  inv = result["inventory_turnover_days"]
  pay = result["payable_turnover_days"]
  if recv && inv && pay
    result["cash_conversion_cycle"] = (recv + inv - pay).round(1)
  end

  result
end
```

**data_json 追加キー:**
- `receivable_turnover_days` (decimal) - 売上債権回転日数
- `inventory_turnover_days` (decimal) - 棚卸資産回転日数
- `payable_turnover_days` (decimal) - 仕入債務回転日数
- `cash_conversion_cycle` (decimal) - CCC

### カテゴリ3: 生産性・成長投資指標

```ruby
# FinancialMetric.get_productivity_metrics(fv) を新設

def self.get_productivity_metrics(fv)
  result = {}

  # R&D集約度
  if fv.research_and_development.present? && fv.net_sales.present? && fv.net_sales > 0
    result["rd_intensity"] = safe_divide(fv.research_and_development, fv.net_sales)&.to_f
  end

  # 設備投資比率
  if fv.capital_expenditure.present? && fv.net_sales.present? && fv.net_sales > 0
    result["capex_ratio"] = safe_divide(fv.capital_expenditure, fv.net_sales)&.to_f
  end

  # 設備投資/償却倍率
  depreciation = fv.depreciation_and_amortization || fv.depreciation_summary
  if fv.capital_expenditure.present? && depreciation.present? && depreciation > 0
    result["capex_to_depreciation"] = safe_divide(fv.capital_expenditure, depreciation)&.to_f
  end

  # 1人あたり売上高
  if fv.number_of_employees.present? && fv.number_of_employees > 0
    if fv.net_sales.present?
      result["revenue_per_employee"] = (fv.net_sales.to_d / fv.number_of_employees).to_f
    end
    if fv.operating_income.present?
      result["operating_income_per_employee"] = (fv.operating_income.to_d / fv.number_of_employees).to_f
    end
  end

  # 実効税率
  if fv.income_taxes.present? && fv.income_before_income_taxes.present? && fv.income_before_income_taxes > 0
    result["effective_tax_rate"] = safe_divide(fv.income_taxes, fv.income_before_income_taxes)&.to_f
  end

  # のれん比率
  if fv.goodwill.present? && fv.total_assets.present? && fv.total_assets > 0
    result["goodwill_ratio"] = safe_divide(fv.goodwill, fv.total_assets)&.to_f
  end

  result
end
```

**data_json 追加キー:**
- `rd_intensity` (decimal) - R&D / 売上高
- `capex_ratio` (decimal) - 設備投資 / 売上高
- `capex_to_depreciation` (decimal) - 設備投資 / 減価償却
- `revenue_per_employee` (decimal) - 1人あたり売上高
- `operating_income_per_employee` (decimal) - 1人あたり営業利益
- `effective_tax_rate` (decimal) - 実効税率
- `goodwill_ratio` (decimal) - のれん比率

### CalculateFinancialMetricsJob の更新

```ruby
def calculate_metrics_for(fv)
  # ... 既存の計算 ...

  # 新指標の計算
  ebitda = FinancialMetric.get_ebitda_metrics(fv, stock_price)
  working_capital = FinancialMetric.get_working_capital_metrics(fv)
  productivity = FinancialMetric.get_productivity_metrics(fv)

  # data_json にマージ
  data_json.merge!(ebitda).merge!(working_capital).merge!(productivity)
end
```

### FinancialMetric の data_json スキーマ拡張

```ruby
define_json_attributes :data_json, schema: {
  # ... 既存スキーマ ...

  # EBITDA・有利子負債
  ebitda: { type: :integer },
  ebitda_margin: { type: :decimal },
  interest_bearing_debt: { type: :integer },
  net_debt: { type: :integer },
  debt_to_ebitda: { type: :decimal },
  interest_coverage_ratio: { type: :decimal },

  # 運転資本・CCC
  receivable_turnover_days: { type: :decimal },
  inventory_turnover_days: { type: :decimal },
  payable_turnover_days: { type: :decimal },
  cash_conversion_cycle: { type: :decimal },

  # 生産性・成長投資
  rd_intensity: { type: :decimal },
  capex_ratio: { type: :decimal },
  capex_to_depreciation: { type: :decimal },
  revenue_per_employee: { type: :decimal },
  operating_income_per_employee: { type: :decimal },
  effective_tax_rate: { type: :decimal },
  goodwill_ratio: { type: :decimal },
}
```

## テスト

### FinancialMetric のテスト

各メソッドに対して以下をテスト:
- 正常な入力値での計算結果の正確性
- 必要なデータが欠落している場合に安全にnil/空Hashを返すこと
- ゼロ除算の回避（safe_divideの動作確認）
- 負の値の適切な処理（支払利息がマイナス等）

### CalculateFinancialMetricsJob のテスト

- 新指標が正しくdata_jsonに格納されること
- 既存指標の計算に影響がないこと

## 注意事項

- 全ての新指標は data_json に格納するため、マイグレーション不要
- 拡張データがnilの企業（JQUANTSのみの取り込み等）では新指標もnilとなる
- 金融業では一部指標（CCC等）が意味をなさないため、SectorMetric でのフィルタリングが必要になる可能性あり
- 既存の get_ev_ebitda を get_ebitda_metrics に統合する際、既存データとの互換性に注意

## 優先度

中。XBRL要素拡張の完了後に実施。

## 依存関係

- 先行: `dev_xbrl_jppfs_element_expansion` + `dev_xbrl_jpcrp_namespace_support`
- 関連: `dev_edinet_xbrl_per_share_data_extraction`（EPS/BPSの正確な取得はバリュエーション指標に影響）
