class ImportFinancialStatementsJob < ApplicationJob
  queue_as :default

  # Import financial statements
  # @param code [String] Optional stock code to limit to specific company
  # @param date [String] Optional date (YYYY-MM-DD)
  def perform(code: nil, date: nil)
    client = Jquants::Client.new
    statements_data = client.financial_summary(code: code, date: date)

    return unless statements_data

    imported_count = 0
    updated_count = 0

    statements_data.each do |statement_data|
      stock_code = statement_data["Code"]
      next unless stock_code

      company = Company.find_by(code: stock_code)
      next unless company

      # Extract fiscal year and period information
      # Use CurPerType (1Q, 2Q, 3Q, 4Q, FY) as fiscal_period
      fiscal_period = statement_data["CurPerType"]
      # Extract fiscal year from CurFYEn (e.g., "2024-03-31" -> 2024)
      fiscal_year = statement_data["CurFYEn"] ? Date.parse(statement_data["CurFYEn"]).year : nil
      next unless fiscal_year && fiscal_period

      statement = FinancialStatement.find_or_initialize_by(
        company: company,
        fiscal_year: fiscal_year,
        fiscal_period: fiscal_period
      )

      if statement.new_record?
        imported_count += 1
      else
        updated_count += 1
      end

      statement.update!(
        report_type: statement_data["DocType"],
        net_sales: statement_data["Sales"],
        operating_income: statement_data["OP"],
        ordinary_income: statement_data["OdP"],
        net_income: statement_data["NP"],
        total_assets: statement_data["TA"],
        total_equity: statement_data["Eq"],
        operating_cash_flow: statement_data["CFO"],
        investing_cash_flow: statement_data["CFI"],
        financing_cash_flow: statement_data["CFF"],
        shares_outstanding: statement_data["ShOutFY"],
        filed_date: statement_data["DiscDate"] ? Date.parse(statement_data["DiscDate"]) : nil
      )
    end

    Rails.logger.info "Financial statements import completed: #{imported_count} new, #{updated_count} updated"
  end
end
