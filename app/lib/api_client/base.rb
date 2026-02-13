require "faraday"
require "faraday/retry"
require "json"

module ApiClient
  class Base
    attr_reader :base_url, :rate_limiter, :logger

    def initialize(base_url:, rate_limiter: nil, logger: nil)
      @base_url = base_url
      @rate_limiter = rate_limiter
      @logger = logger || Rails.logger
      @connection = build_connection
    end

    protected

    def get(path, params: {}, headers: {})
      request(:get, path, params: params, headers: headers)
    end

    def post(path, body: {}, params: {}, headers: {})
      request(:post, path, body: body, params: params, headers: headers)
    end

    def put(path, body: {}, params: {}, headers: {})
      request(:put, path, body: body, params: params, headers: headers)
    end

    def delete(path, params: {}, headers: {})
      request(:delete, path, params: params, headers: headers)
    end

    private

    def build_connection
      Faraday.new(url: @base_url) do |conn|
        conn.request :json
        conn.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
                            exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
      end
    end

    def request(method, path, params: {}, body: {}, headers: {})
      execute_with_rate_limit do
        log_request(method, path, params)

        response = case method
                   when :get, :delete
                     @connection.public_send(method, path, params, headers)
                   when :post, :put
                     @connection.public_send(method, path, body) do |req|
                       req.headers.update(headers)
                       req.params.update(params) if params.any?
                     end
        end

        log_response(response)
        handle_response(response)
      end
    rescue Faraday::Error => e
      log_error(e)
      raise ApiClient::Errors::NetworkError.new("Network error: #{e.message}")
    end

    def execute_with_rate_limit(&block)
      if @rate_limiter
        @rate_limiter.throttle(&block)
      else
        yield
      end
    end

    def handle_response(response)
      case response.status
      when 200..299
        response
      when 401, 403
        raise ApiClient::Errors::AuthenticationError.new("Authentication failed: #{response.status}")
      when 429
        raise ApiClient::Errors::RateLimitError.new("Rate limit exceeded")
      when 400..499
        raise ApiClient::Errors::ClientError.new("Client error: #{response.status} - #{response.body}")
      when 500..599
        raise ApiClient::Errors::ServerError.new("Server error: #{response.status}")
      else
        raise ApiClient::Errors::ApiError.new("Unexpected response: #{response.status}")
      end
    end

    def log_request(method, path, params)
      return unless @logger

      @logger.info("[API Request] #{method.upcase} #{path} #{params.inspect}")
    end

    def log_response(response)
      return unless @logger

      @logger.info("[API Response] Status: #{response.status}")
    end

    def log_error(error)
      return unless @logger

      @logger.error("[API Error] #{error.class}: #{error.message}")
    end
  end
end
