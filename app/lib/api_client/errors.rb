module ApiClient
  module Errors
    class ApiError < StandardError; end
    class AuthenticationError < ApiError; end
    class RateLimitError < ApiError; end
    class ClientError < ApiError; end
    class ServerError < ApiError; end
    class NetworkError < ApiError; end
  end
end
