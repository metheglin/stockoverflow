class FinancialStatement < ApplicationRecord
  belongs_to :company

  validates :fiscal_year, presence: true
  validates :fiscal_period, presence: true
  validates :fiscal_year, uniqueness: { scope: [:company_id, :fiscal_period] }

  scope :annual, -> { where(fiscal_period: "FY") }
  scope :quarterly, -> { where.not(fiscal_period: "FY") }
  scope :for_year, ->(year) { where(fiscal_year: year) }
  scope :ordered, -> { order(fiscal_year: :asc, fiscal_period: :asc) }

  def eps
    return nil unless net_income && shares_outstanding && shares_outstanding > 0
    net_income / shares_outstanding.to_d
  end
end
