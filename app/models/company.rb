class Company < ApplicationRecord
  has_many :financial_statements, dependent: :destroy
  has_many :stock_prices, dependent: :destroy
  has_many :growth_metrics, dependent: :destroy
  has_many :profitability_metrics, dependent: :destroy
  has_many :valuation_metrics, dependent: :destroy
  has_many :cash_flow_metrics, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
end
