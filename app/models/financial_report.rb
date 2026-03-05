class FinancialReport < ApplicationRecord
  belongs_to :company
  has_one :financial_value

  enum :report_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
    semi_annual: 4,
    other: 9,
  }

  enum :source, {
    edinet: 0,
    jquants: 1,
    manual: 2,
  }
end
