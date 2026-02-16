class ProfitabilityMetric < ApplicationRecord
  belongs_to :company

  validates :fiscal_year, presence: true
  validates :fiscal_period, presence: true
  validates :fiscal_year, uniqueness: { scope: [:company_id, :fiscal_period] }

  scope :annual, -> { where(fiscal_period: "FY") }
  scope :ordered, -> { order(fiscal_year: :asc) }
end
