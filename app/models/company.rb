class Company < ApplicationRecord
  has_many :financial_reports, dependent: :destroy
  has_many :financial_values, dependent: :destroy
  has_many :financial_metrics, dependent: :destroy
  has_many :daily_quotes, dependent: :destroy

  scope :listed, -> { where(listed: true) }
end
