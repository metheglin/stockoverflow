module Edinet
  class Client < ApiClient::Base
    BASE_URL = "https://api.edinet-fsa.go.jp/api/v2"

    def initialize(api_key: ENV["EDINET_API_KEY"])
      @api_key = api_key
      rate_limiter = ApiClient::RateLimiter.new(max_requests: 10, period: 60)
      super(base_url: BASE_URL, rate_limiter: rate_limiter)
    end

    # List documents filed on a given date
    # type: 1 = metadata only, 2 = include document list
    def documents(date:, type: 2)
      params = {
        date: date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date,
        type: type,
        "Subscription-Key" => @api_key
      }
      get("documents.json", params)
    end

    # Get a specific document by docID
    # type: 1 = zip with XBRL, 2 = PDF, 3 = attachment, 4 = English docs
    def document(doc_id, type: 1)
      params = {
        type: type,
        "Subscription-Key" => @api_key
      }
      get("documents/#{doc_id}", params)
    end
  end
end
