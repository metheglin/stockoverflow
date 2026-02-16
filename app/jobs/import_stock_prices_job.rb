class ImportStockPricesJob < ApplicationJob
  queue_as :default

  def perform(code: nil, from: nil, to: nil)
    client = Jquants::Client.new
    imported = 0
    skipped = 0

    client.daily_quotes(code: code, from: from, to: to).each do |price_data|
      stock_code = price_data["Code"]
      date_str = price_data["Date"]
      next unless stock_code.present? && date_str.present?

      company = Company.find_by(code: stock_code)
      unless company
        skipped += 1
        next
      end

      date = Date.parse(date_str)
      stock_price = StockPrice.find_or_initialize_by(company: company, date: date)
      stock_price.assign_attributes(
        open_price: price_data["O"],
        high_price: price_data["H"],
        low_price: price_data["L"],
        close_price: price_data["C"],
        volume: price_data["Vo"],
        adjusted_close: price_data["AdjC"]
      )

      if stock_price.changed?
        stock_price.save!
        imported += 1
      else
        skipped += 1
      end
    end

    Rails.logger.info "ImportStockPricesJob: imported=#{imported}, skipped=#{skipped}"
    { imported: imported, skipped: skipped }
  end
end
