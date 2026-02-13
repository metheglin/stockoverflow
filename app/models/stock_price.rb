class StockPrice < ApplicationRecord
  belongs_to :company

  validates :date, presence: true

  scope :by_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, -> { order(date: :desc) }
end
