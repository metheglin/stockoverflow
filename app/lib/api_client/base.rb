module ApiClient
  class Base
    include Errors

    def initialize(base_url:, rate_limiter: nil)
      @base_url = base_url
      @rate_limiter = rate_limiter
      @connection = build_connection
    end

    private

    def get(path, params = {}, headers = {})
      request(:get, path, params, headers)
    end

    def request(method, path, params = {}, headers = {})
      response = if @rate_limiter
        @rate_limiter.throttle { perform_request(method, path, params, headers) }
      else
        perform_request(method, path, params, headers)
      end

      handle_response(response)
    end

    def perform_request(method, path, params, headers)
      @connection.send(method) do |req|
        req.url path
        req.params = params if params.any?
        headers.each { |k, v| req.headers[k] = v }
      end
    end

    def handle_response(response)
      case response.status
      when 200..299
        parse_response(response)
      when 401
        raise AuthenticationError.new(status: response.status, body: response.body)
      when 403
        raise ForbiddenError.new(status: response.status, body: response.body)
      when 404
        raise NotFoundError.new(status: response.status, body: response.body)
      when 429
        raise RateLimitError.new(status: response.status, body: response.body)
      when 400..499
        raise ClientError.new(status: response.status, body: response.body)
      when 500..599
        raise ServerError.new(status: response.status, body: response.body)
      else
        raise ApiError.new("Unexpected response status: #{response.status}", status: response.status, body: response.body)
      end
    end

    def parse_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      response.body
    end

    def build_connection
      Faraday.new(url: @base_url) do |conn|
        conn.request :retry, max: 3, interval: 1, backoff_factor: 2,
          exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        conn.response :raise_error, false
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
