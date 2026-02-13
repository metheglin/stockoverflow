class Company < ApplicationRecord
  has_many :financial_statements, dependent: :destroy
  has_many :stock_prices, dependent: :destroy
  has_many :growth_metrics, dependent: :destroy
  has_many :profitability_metrics, dependent: :destroy
  has_many :valuation_metrics, dependent: :destroy
  has_many :cash_flow_metrics, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  # Scope: Companies with N consecutive periods of positive revenue growth
  scope :with_consecutive_revenue_growth, ->(periods = 6) {
    joins(:growth_metrics)
      .group("companies.id")
      .having("COUNT(CASE WHEN growth_metrics.revenue_growth_rate > 0 THEN 1 END) >= ?", periods)
      .select("companies.*, AVG(growth_metrics.revenue_growth_rate) as avg_revenue_growth")
      .order("avg_revenue_growth DESC")
  }

  # Scope: Companies with N consecutive periods of positive profit growth
  scope :with_consecutive_profit_growth, ->(periods = 6) {
    joins(:growth_metrics)
      .group("companies.id")
      .having("COUNT(CASE WHEN growth_metrics.net_income_growth_rate > 0 THEN 1 END) >= ?", periods)
      .select("companies.*, AVG(growth_metrics.net_income_growth_rate) as avg_profit_growth")
      .order("avg_profit_growth DESC")
  }

  # Scope: Companies with positive OCF and negative ICF
  scope :with_positive_ocf_negative_icf, -> {
    joins(:cash_flow_metrics, :financial_statements)
      .where("financial_statements.operating_cash_flow > 0")
      .where("financial_statements.investing_cash_flow < 0")
      .distinct
  }

  # Scope: Companies where OCF-ICF gap turned positive
  scope :with_positive_ocf_icf_gap, -> {
    joins(:cash_flow_metrics)
      .where("cash_flow_metrics.ocf_icf_gap > 0")
      .distinct
  }

  # Scope: Companies by industry
  scope :by_industry, ->(industry) {
    where(industry: industry)
  }

  # Scope: Companies by market
  scope :by_market, ->(market) {
    where(market: market)
  }

  # Find companies with high ROE (above threshold)
  scope :high_roe, ->(threshold = 15) {
    joins(:profitability_metrics)
      .where("profitability_metrics.roe >= ?", threshold)
      .distinct
  }

  # Find companies with high ROA (above threshold)
  scope :high_roa, ->(threshold = 10) {
    joins(:profitability_metrics)
      .where("profitability_metrics.roa >= ?", threshold)
      .distinct
  }

  # Instance methods for analysis

  def latest_financial_statement
    financial_statements.order(fiscal_year: :desc, fiscal_period: :desc).first
  end

  def latest_stock_price
    stock_prices.order(date: :desc).first
  end

  def growth_trend(periods: 4)
    growth_metrics.order(fiscal_year: :desc, fiscal_period: :desc).limit(periods)
  end

  def profitability_trend(periods: 4)
    profitability_metrics.order(fiscal_year: :desc, fiscal_period: :desc).limit(periods)
  end

  def cash_flow_trend(periods: 4)
    cash_flow_metrics.order(fiscal_year: :desc, fiscal_period: :desc).limit(periods)
  end

  # Check if company has consecutive revenue growth
  def consecutive_revenue_growth?(periods: 6)
    growth_metrics.where("revenue_growth_rate > 0")
                  .order(fiscal_year: :desc, fiscal_period: :desc)
                  .limit(periods)
                  .count == periods
  end

  # Check if company has consecutive profit growth
  def consecutive_profit_growth?(periods: 6)
    growth_metrics.where("net_income_growth_rate > 0")
                  .order(fiscal_year: :desc, fiscal_period: :desc)
                  .limit(periods)
                  .count == periods
  end

  # Get historical metrics summary
  def metrics_summary
    {
      code: code,
      name: name,
      industry: industry,
      market: market,
      latest_statement: latest_financial_statement,
      latest_price: latest_stock_price,
      avg_roe: profitability_metrics.average(:roe)&.round(2),
      avg_roa: profitability_metrics.average(:roa)&.round(2),
      avg_revenue_growth: growth_metrics.average(:revenue_growth_rate)&.round(2),
      avg_profit_growth: growth_metrics.average(:net_income_growth_rate)&.round(2)
    }
  end
end
