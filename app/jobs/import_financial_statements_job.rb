class ImportFinancialStatementsJob < ApplicationJob
  queue_as :default

  # Import financial statements
  # @param code [String] Optional stock code to limit to specific company
  # @param date [String] Optional date (YYYY-MM-DD)
  def perform(code: nil, date: nil)
    client = JquantsClient.new
    data = client.financial_statements(code: code, date: date)

    return unless data && data["statements"]

    statements_data = data["statements"]
    imported_count = 0
    updated_count = 0

    statements_data.each do |statement_data|
      stock_code = statement_data["Code"]
      next unless stock_code

      company = Company.find_by(code: stock_code)
      next unless company

      # Extract fiscal year and period
      fiscal_year = statement_data["FiscalYear"]
      fiscal_period = statement_data["FiscalPeriod"]
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
        report_type: statement_data["TypeOfDocument"],
        net_sales: statement_data["NetSales"],
        operating_income: statement_data["OperatingIncome"],
        ordinary_income: statement_data["OrdinaryIncome"],
        net_income: statement_data["NetIncome"],
        total_assets: statement_data["TotalAssets"],
        total_equity: statement_data["Equity"],
        operating_cash_flow: statement_data["CashFlowsFromOperatingActivities"],
        investing_cash_flow: statement_data["CashFlowsFromInvestingActivities"],
        financing_cash_flow: statement_data["CashFlowsFromFinancingActivities"],
        shares_outstanding: statement_data["IssuedShareNumber"],
        filed_date: statement_data["DisclosedDate"] ? Date.parse(statement_data["DisclosedDate"]) : nil
      )
    end

    Rails.logger.info "Financial statements import completed: #{imported_count} new, #{updated_count} updated"
  end
end
