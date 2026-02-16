class ImportCompaniesJob < ApplicationJob
  queue_as :default

  def perform
    client = Jquants::Client.new
    imported = 0
    skipped = 0

    client.listed_companies.each do |company_data|
      stock_code = company_data["Code"]
      next unless stock_code.present?

      company = Company.find_or_initialize_by(code: stock_code)
      company.assign_attributes(
        name: company_data["CoName"],
        market: company_data["MktNm"],
        industry: company_data["S33Nm"],
        sector: company_data["S17Nm"],
        listing_date: parse_date(company_data["ListingDate"])
      )

      if company.changed?
        company.save!
        imported += 1
      else
        skipped += 1
      end
    end

    Rails.logger.info "ImportCompaniesJob: imported=#{imported}, skipped=#{skipped}"
    { imported: imported, skipped: skipped }
  end

  private

  def parse_date(date_str)
    return nil if date_str.blank?
    Date.parse(date_str)
  rescue Date::Error
    nil
  end
end
