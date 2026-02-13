require "faraday"
require "faraday/retry"
require "json"

class JquantsClient
  BASE_URL = "https://api.jquants.com/v1"
  ID_TOKEN_URL = "https://api.jquants.com/v1/token/auth_user"
  REFRESH_TOKEN_URL = "https://api.jquants.com/v1/token/auth_refresh"

  def initialize(api_key: nil)
    @api_key = api_key || ENV["JQUANTS_API_KEY"]
    @id_token = nil
    @connection = build_connection
  end

  # Get listed companies information
  # @return [Hash] API response
  def listed_companies
    response = get_with_auth("listed/info")
    handle_response(response)
  end

  # Get stock prices for a date or date range
  # @param code [String] Optional stock code (4 digits)
  # @param date [String] Optional date (YYYY-MM-DD)
  # @param from [String] Optional start date (YYYY-MM-DD)
  # @param to [String] Optional end date (YYYY-MM-DD)
  # @return [Hash] API response
  def stock_prices(code: nil, date: nil, from: nil, to: nil)
    params = {}
    params["code"] = code if code
    params["date"] = date if date
    params["from"] = from if from
    params["to"] = to if to

    response = get_with_auth("prices/daily_quotes", params)
    handle_response(response)
  end

  # Get financial statements
  # @param code [String] Optional stock code (4 digits)
  # @param date [String] Optional date (YYYY-MM-DD)
  # @return [Hash] API response
  def financial_statements(code: nil, date: nil)
    params = {}
    params["code"] = code if code
    params["date"] = date if date

    response = get_with_auth("fins/statements", params)
    handle_response(response)
  end

  # Get financial announcement data
  # @param code [String] Optional stock code (4 digits)
  # @param date [String] Optional date (YYYY-MM-DD)
  # @return [Hash] API response
  def financial_announcements(code: nil, date: nil)
    params = {}
    params["code"] = code if code
    params["date"] = date if date

    response = get_with_auth("fins/announcement", params)
    handle_response(response)
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.request :retry, max: 3, interval: 0.5, backoff_factor: 2
      conn.response :raise_error
      conn.adapter Faraday.default_adapter
    end
  end

  def get_with_auth(path, params = {})
    ensure_authenticated!

    @connection.get(path) do |req|
      req.headers["Authorization"] = "Bearer #{@id_token}"
      params.each { |key, value| req.params[key] = value }
    end
  end

  def ensure_authenticated!
    return if @id_token

    authenticate!
  end

  def authenticate!
    conn = Faraday.new(url: ID_TOKEN_URL)
    response = conn.post do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { mailaddress: @api_key }.to_json
    end

    if response.success?
      data = JSON.parse(response.body)
      @id_token = data["idToken"]
      @refresh_token = data["refreshToken"]
    else
      raise "Failed to authenticate with JQUANTS API: #{response.status}"
    end
  end

  def refresh_token!
    return unless @refresh_token

    conn = Faraday.new(url: REFRESH_TOKEN_URL)
    response = conn.post do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { refreshtoken: @refresh_token }.to_json
    end

    if response.success?
      data = JSON.parse(response.body)
      @id_token = data["idToken"]
    else
      authenticate!
    end
  end

  def handle_response(response)
    return nil unless response.success?

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JQUANTS API response: #{e.message}")
      nil
    end
  end
end
