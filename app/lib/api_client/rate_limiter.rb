module ApiClient
  class RateLimiter
    def initialize(min_interval:)
      @min_interval = min_interval
      @last_request_time = nil
      @mutex = Mutex.new
    end

    def wait_if_needed
      @mutex.synchronize do
        return unless @last_request_time

        elapsed = Time.now - @last_request_time
        sleep_time = @min_interval - elapsed

        sleep(sleep_time) if sleep_time > 0
      end
    end

    def record_request
      @mutex.synchronize do
        @last_request_time = Time.now
      end
    end

    def throttle
      wait_if_needed
      yield
    ensure
      record_request
    end
  end
end
