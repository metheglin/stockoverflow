class CashFlowMetric < ApplicationRecord
  belongs_to :company

  validates :fiscal_year, presence: true
  validates :fiscal_period, presence: true

  scope :by_year, ->(year) { where(fiscal_year: year) }
  scope :recent, -> { order(fiscal_year: :desc, fiscal_period: :desc) }
end
