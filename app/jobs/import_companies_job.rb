class ImportCompaniesJob < ApplicationJob
  queue_as :default

  def perform
    client = Jquants::Client.new
    companies_data = client.listed_companies

    return unless companies_data

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
        name: company_data["CoName"],
        market: company_data["MktNm"],
        industry: company_data["S33Nm"],
        sector: company_data["S17Nm"]
      )
    end

    Rails.logger.info "Companies import completed: #{imported_count} new, #{updated_count} updated"
  end
end
