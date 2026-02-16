class ImportFinancialStatementsJob < ApplicationJob
  queue_as :default

  def perform(code: nil)
    client = Jquants::Client.new
    imported = 0
    skipped = 0

    client.fins_statements(code: code).each do |statement_data|
      stock_code = statement_data["Code"]
      next unless stock_code.present?

      company = Company.find_by(code: stock_code)
      unless company
        skipped += 1
        next
      end

      # Extract fiscal period type (1Q, 2Q, 3Q, 4Q, FY)
      fiscal_period = statement_data["CurPerType"]
      # Extract fiscal year from CurFYEn (e.g., "2024-03-31" -> 2024)
      fiscal_year = extract_fiscal_year(statement_data["CurFYEn"])
      next unless fiscal_year && fiscal_period.present?

      statement = FinancialStatement.find_or_initialize_by(
        company: company,
        fiscal_year: fiscal_year,
        fiscal_period: fiscal_period
      )

      statement.assign_attributes(
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
        filed_date: parse_date(statement_data["DiscDate"])
      )

      if statement.changed?
        statement.save!
        imported += 1
      else
        skipped += 1
      end
    end

    Rails.logger.info "ImportFinancialStatementsJob: imported=#{imported}, skipped=#{skipped}"
    { imported: imported, skipped: skipped }
  end

  private

  def extract_fiscal_year(fy_end_str)
    return nil if fy_end_str.blank?
    Date.parse(fy_end_str).year
  rescue Date::Error
    nil
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    Date.parse(date_str)
  rescue Date::Error
    nil
  end
end
