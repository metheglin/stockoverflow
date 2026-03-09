class Company < ApplicationRecord
  # JQUANTS V2 listed info → companies カラム マッピング
  JQUANTS_FIELD_MAP = {
    "Code"      => :securities_code,
    "CoName"    => :name,
    "CoNameEn"  => :name_english,
    "S17"       => :sector_17_code,
    "S17Nm"     => :sector_17_name,
    "S33"       => :sector_33_code,
    "S33Nm"     => :sector_33_name,
    "ScaleCat"  => :scale_category,
    "Mkt"       => :market_code,
    "MktNm"     => :market_name,
  }.freeze

  # JQUANTS V2 listed info のうち data_json に格納するフィールド
  JQUANTS_DATA_JSON_FIELDS = %w[Mrgn MrgnNm].freeze

  has_many :financial_reports, dependent: :destroy
  has_many :financial_values, dependent: :destroy
  has_many :financial_metrics, dependent: :destroy
  has_many :daily_quotes, dependent: :destroy

  scope :listed, -> { where(listed: true) }

  # JQUANTS V2 listed info のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1銘柄分のHash
  # @return [Hash] Company.create / update に渡せる属性Hash
  #
  # 例:
  #   attrs = Company.get_attributes_from_jquants(jquants_data)
  #   # => { securities_code: "86970", name: "日本取引所グループ", ... }
  #
  def self.get_attributes_from_jquants(data)
    attrs = {}
    JQUANTS_FIELD_MAP.each do |jquants_key, column|
      attrs[column] = data[jquants_key] if data.key?(jquants_key)
    end

    # data_json に格納するフィールド
    json_data = {}
    JQUANTS_DATA_JSON_FIELDS.each do |key|
      json_data[key.underscore] = data[key] if data.key?(key)
    end
    attrs[:data_json] = json_data if json_data.any?
    attrs[:listed] = true

    attrs
  end
end
