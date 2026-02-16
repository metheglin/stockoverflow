class StockPrice < ApplicationRecord
  belongs_to :company

  validates :date, presence: true
  validates :date, uniqueness: { scope: :company_id }

  scope :for_date_range, ->(from, to) { where(date: from..to) }
  scope :ordered, -> { order(date: :asc) }
  scope :latest, -> { order(date: :desc).limit(1) }
end
