class ImportCompaniesJob < ApplicationJob
  queue_as :default

  def perform
    client = JquantsClient.new
    data = client.listed_companies

    return unless data && data["info"]

    companies_data = data["info"]
    imported_count = 0
    updated_count = 0

    companies_data.each do |company_data|
      code = company_data["Code"]
      next unless code

      company = Company.find_or_initialize_by(code: code)

      if company.new_record?
        imported_count += 1
      else
        updated_count += 1
      end

      company.update!(
        name: company_data["CompanyName"],
        market: company_data["MarketCode"],
        industry: company_data["33SectorName"],
        sector: company_data["17SectorName"]
      )
    end

    Rails.logger.info "Companies import completed: #{imported_count} new, #{updated_count} updated"
  end
end
