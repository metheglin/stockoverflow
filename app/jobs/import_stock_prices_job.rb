class ImportStockPricesJob < ApplicationJob
  queue_as :default

  # Import stock prices for a date range
  # @param from [String] Start date (YYYY-MM-DD)
  # @param to [String] End date (YYYY-MM-DD)
  # @param code [String] Optional stock code to limit to specific company
  def perform(from:, to:, code: nil)
    client = Jquants::Client.new
    prices_data = client.daily_prices(from: from, to: to, code: code)

    return unless prices_data

    imported_count = 0
    updated_count = 0

    prices_data.each do |price_data|
      stock_code = price_data["Code"]
      next unless stock_code

      company = Company.find_by(code: stock_code)
      next unless company

      date = Date.parse(price_data["Date"])
      stock_price = StockPrice.find_or_initialize_by(company: company, date: date)

      if stock_price.new_record?
        imported_count += 1
      else
        updated_count += 1
      end

      stock_price.update!(
        open_price: price_data["Open"],
        high_price: price_data["High"],
        low_price: price_data["Low"],
        close_price: price_data["Close"],
        volume: price_data["Volume"],
        adjusted_close: price_data["AdjustmentClose"]
      )
    end

    Rails.logger.info "Stock prices import completed: #{imported_count} new, #{updated_count} updated"
  end
end
