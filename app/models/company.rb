class Company < ApplicationRecord
  has_many :financial_statements, dependent: :destroy
  has_many :stock_prices, dependent: :destroy
  has_many :growth_metrics, dependent: :destroy
  has_many :profitability_metrics, dependent: :destroy
  has_many :valuation_metrics, dependent: :destroy
  has_many :cash_flow_metrics, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :by_market, ->(market) { where(market: market) }
  scope :by_industry, ->(industry) { where(industry: industry) }
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :listed, -> { where.not(listing_date: nil) }
  scope :search_by_name, ->(query) { where("name LIKE ?", "%#{query}%") }

  # Find companies with N consecutive periods of revenue growth
  def self.with_consecutive_revenue_growth(periods = 6)
    CompanyAnalyzer.consecutive_growth(periods: periods, metric: :revenue_growth_rate)
  end

  # Find companies with N consecutive periods of operating income growth
  def self.with_consecutive_profit_growth(periods = 6)
    CompanyAnalyzer.consecutive_growth(periods: periods, metric: :operating_income_growth_rate)
  end

  # Find companies with cash flow turnaround pattern
  def self.with_cash_flow_turnaround
    CompanyAnalyzer.cash_flow_turnaround
  end

  # Get full analysis profile for this company
  def profile
    CompanyAnalyzer.company_profile(self)
  end
end
