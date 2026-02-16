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
      paginate("equities/master", params)
    end

    # Fetch daily stock prices
    def daily_quotes(code: nil, from: nil, to: nil)
      params = {}
      params[:code] = code if code
      params[:from] = from if from
      params[:to] = to if to
      paginate("equities/bars/daily", params)
    end

    # Fetch financial statement summaries
    def fins_statements(code: nil, date: nil)
      params = {}
      params[:code] = code if code
      params[:date] = date if date
      paginate("fins/summary", params)
    end

    private

    def get(path, params = {}, headers = {})
      headers["x-api-key"] = @api_key
      super(path, params, headers)
    end

    def paginate(path, params)
      Paginator.new(self, path, params)
    end
  end
end
