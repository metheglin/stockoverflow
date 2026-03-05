class FinancialMetric < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_value

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
    # バリュエーション指標
    per: { type: :decimal },
    pbr: { type: :decimal },
    psr: { type: :decimal },
    dividend_yield: { type: :decimal },
    ev_ebitda: { type: :decimal },
  }
end
