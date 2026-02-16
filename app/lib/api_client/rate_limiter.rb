module ApiClient
  class RateLimiter
    def initialize(max_requests:, period:)
      @max_requests = max_requests
      @period = period
      @mutex = Mutex.new
      @timestamps = []
    end

    def throttle
      @mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @timestamps.reject! { |t| now - t > @period }

        if @timestamps.size >= @max_requests
          sleep_time = @period - (now - @timestamps.first)
          if sleep_time > 0
            @mutex.unlock
            sleep(sleep_time)
            @mutex.lock
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @timestamps.reject! { |t| now - t > @period }
          end
        end

        @timestamps << Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      yield
    end
  end
end
