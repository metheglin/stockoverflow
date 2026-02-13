module Jquants
  class Paginator
    include Enumerable

    def initialize(client:, path:, params:)
      @client = client
      @path = path
      @params = params
      @pagination_key = nil
    end

    # Iterate over all pages and yield each item
    def each(&block)
      return enum_for(:each) unless block_given?

      all.each(&block)
    end

    # Fetch all items from all pages
    # @return [Array<Hash>]
    def all
      items = []
      each_page do |page_items|
        items.concat(page_items)
      end
      items
    end

    # Iterate over pages (yields array of items per page)
    def each_page
      return enum_for(:each_page) unless block_given?

      loop do
        response = fetch_page
        data = response.body

        # Handle different response formats
        items = extract_items(data)
        yield items if items.any?

        # Check for pagination key
        @pagination_key = data["pagination_key"]
        break unless @pagination_key
      end
    end

    # Get the first page of results
    # @return [Array<Hash>]
    def first_page
      response = fetch_page
      extract_items(response.body)
    end

    # Get the first N items
    # @param n [Integer] Number of items to fetch
    # @return [Array<Hash>]
    def first(n = 1)
      items = []
      each do |item|
        items << item
        break if items.size >= n
      end
      items
    end

    # Count total items (requires fetching all pages)
    # @return [Integer]
    def count
      all.count
    end

    private

    def fetch_page
      params = @params.dup
      params[:pagination_key] = @pagination_key if @pagination_key

      @client.send(:authenticated_get, @path, params: params)
    end

    def extract_items(data)
      # Try common patterns for item arrays
      return data if data.is_a?(Array)
      return data["data"] if data.is_a?(Hash) && data["data"].is_a?(Array)
      return data["items"] if data.is_a?(Hash) && data["items"].is_a?(Array)

      # If we can't find items, return the data as-is wrapped in array
      # This handles cases where the entire response is the item
      [data].compact
    end
  end
end
