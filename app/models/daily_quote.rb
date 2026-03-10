class DailyQuote < ApplicationRecord
  # JQUANTS V2 bars/daily → daily_quotes 固定カラム マッピング
  JQUANTS_FIELD_MAP = {
    "O"         => :open_price,
    "H"         => :high_price,
    "L"         => :low_price,
    "C"         => :close_price,
    "Vo"        => :volume,
    "Va"        => :turnover_value,
    "AdjFactor" => :adjustment_factor,
    "AdjC"      => :adjusted_close,
  }.freeze

  # JQUANTS V2 bars/daily → daily_quotes data_json マッピング
  JQUANTS_DATA_JSON_FIELDS = %w[AdjO AdjH AdjL AdjVo].freeze

  # 整数として扱うカラム
  INTEGER_COLUMNS = %i[volume turnover_value].freeze

  belongs_to :company

  # JQUANTS V2 bars/daily のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1件分のHash
  # @return [Hash] DailyQuote.create / update に渡せる属性Hash
  #
  # 例:
  #   attrs = DailyQuote.get_attributes_from_jquants(data)
  #   # => { open_price: 2047.0, high_price: 2069.0, ... }
  #
  def self.get_attributes_from_jquants(data)
    attrs = {}
    JQUANTS_FIELD_MAP.each do |jquants_key, column|
      raw_value = data[jquants_key]
      next if raw_value.nil?

      attrs[column] = INTEGER_COLUMNS.include?(column) ? raw_value.to_i : raw_value
    end

    # data_json に格納するフィールド
    json_data = {}
    JQUANTS_DATA_JSON_FIELDS.each do |key|
      json_data[key.underscore] = data[key] if data[key].present?
    end
    attrs[:data_json] = json_data if json_data.any?

    attrs
  end
end
