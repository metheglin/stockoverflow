module Jquants
  class Client < ApiClient::Base
    BASE_URL = "https://api.jquants.com/v2"

    def initialize(api_key: ENV["JQUANTS_API_KEY"])
      @api_key = api_key
      rate_limiter = ApiClient::RateLimiter.new(max_requests: 5, period: 60)
      super(base_url: BASE_URL, rate_limiter: rate_limiter)
    end

    # Fetch listed companies master data
    def listed_companies(code: nil)
      params = {}
      params[:code] = code if code
      paginate("listed/info", params, "info")
    end

    # Fetch daily stock prices
    def daily_quotes(code: nil, from: nil, to: nil)
      params = {}
      params[:code] = code if code
      params[:from] = from if from
      params[:to] = to if to
      paginate("prices/daily_quotes", params, "daily_quotes")
    end

    # Fetch financial statement summaries
    def fins_statements(code: nil)
      params = {}
      params[:code] = code if code
      paginate("fins/statements", params, "statements")
    end

    private

    def get(path, params = {}, headers = {})
      headers["Authorization"] = "Bearer #{@api_key}"
      super(path, params, headers)
    end

    def paginate(path, params, data_key)
      Paginator.new(self, path, params, data_key)
    end
  end
end
