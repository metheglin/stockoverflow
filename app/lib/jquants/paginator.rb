module Jquants
  class Paginator
    include Enumerable

    DATA_KEY = "data"

    def initialize(client, path, params)
      @client = client
      @path = path
      @params = params
    end

    def each(&block)
      pagination_key = nil

      loop do
        params = @params.dup
        params[:pagination_key] = pagination_key if pagination_key

        response = @client.send(:get, @path, params)
        records = response[DATA_KEY] || []
        records.each(&block)

        pagination_key = response["pagination_key"]
        break if pagination_key.nil? || pagination_key.empty? || records.empty?
      end
    end
  end
end
