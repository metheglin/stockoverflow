require "faraday"
require "faraday/retry"
require "json"

class EdinetClient
  BASE_URL = "https://api.edinet-fsa.go.jp/api/v2"

  def initialize(api_key: nil)
    @api_key = api_key || ENV["EDINET_API_KEY"]
    @connection = build_connection
  end

  # Get document list for a specific date
  # @param date [Date, String] Target date (YYYY-MM-DD format)
  # @return [Hash] API response
  def document_list(date:, type: 2)
    date_str = date.is_a?(Date) ? date.strftime("%Y-%m-%d") : date
    response = @connection.get("documents.json") do |req|
      req.params["date"] = date_str
      req.params["type"] = type
      req.params["Subscription-Key"] = @api_key
    end

    handle_response(response)
  end

  # Get document metadata
  # @param doc_id [String] Document ID
  # @return [Hash] API response
  def document_metadata(doc_id:)
    response = @connection.get("documents/#{doc_id}") do |req|
      req.params["type"] = 1
      req.params["Subscription-Key"] = @api_key
    end

    handle_response(response)
  end

  # Download XBRL document
  # @param doc_id [String] Document ID
  # @return [String] Document content
  def download_xbrl(doc_id:)
    response = @connection.get("documents/#{doc_id}") do |req|
      req.params["type"] = 5
      req.params["Subscription-Key"] = @api_key
    end

    response.body if response.success?
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.request :retry, max: 3, interval: 0.5, backoff_factor: 2
      conn.response :raise_error
      conn.adapter Faraday.default_adapter
    end
  end

  def handle_response(response)
    return nil unless response.success?

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse EDINET API response: #{e.message}")
      nil
    end
  end
end
