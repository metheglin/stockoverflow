module ApiClient
  module Errors
    class ApiError < StandardError
      attr_reader :status, :body

      def initialize(message = nil, status: nil, body: nil)
        @status = status
        @body = body
        super(message || "API error (status: #{status})")
      end
    end

    class AuthenticationError < ApiError; end
    class ForbiddenError < ApiError; end
    class RateLimitError < ApiError; end
    class ClientError < ApiError; end
    class ServerError < ApiError; end
    class NotFoundError < ApiError; end
  end
end
