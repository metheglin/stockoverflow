class FinancialValue < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_report, optional: true
  has_one :financial_metric

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  define_json_attributes :data_json, schema: {
    # 配当実績
    dividend_per_share_annual: { type: :decimal },
    total_dividend_paid: { type: :integer },
    payout_ratio: { type: :decimal },
    # 業績予想
    forecast_net_sales: { type: :integer },
    forecast_operating_income: { type: :integer },
    forecast_ordinary_income: { type: :integer },
    forecast_net_income: { type: :integer },
    forecast_eps: { type: :decimal },
    # XBRL追加要素
    cost_of_sales: { type: :integer },
    gross_profit: { type: :integer },
    sga_expenses: { type: :integer },
    current_assets: { type: :integer },
    noncurrent_assets: { type: :integer },
    current_liabilities: { type: :integer },
    noncurrent_liabilities: { type: :integer },
    shareholders_equity: { type: :integer },
  }
end
