class FinancialValue < ApplicationRecord
  include JsonAttribute

  # JQUANTS V2 fins/summary → financial_values 固定カラム マッピング（連結）
  JQUANTS_CONSOLIDATED_FIELD_MAP = {
    "Sales"    => :net_sales,
    "OP"       => :operating_income,
    "OdP"      => :ordinary_income,
    "NP"       => :net_income,
    "EPS"      => :eps,
    "DEPS"     => :diluted_eps,
    "TA"       => :total_assets,
    "Eq"       => :net_assets,
    "EqRatio"  => :equity_ratio,
    "BPS"      => :bps,
    "CFO"      => :operating_cf,
    "CFI"      => :investing_cf,
    "CFF"      => :financing_cf,
    "CashEq"   => :cash_and_equivalents,
    "ShOutFY"  => :shares_outstanding,
    "TrShFY"   => :treasury_shares,
  }.freeze

  # JQUANTS V2 fins/summary → financial_values data_json マッピング（連結）
  JQUANTS_CONSOLIDATED_DATA_JSON_MAP = {
    "DivAnn" => "dividend_per_share_annual",
    "FSales" => "forecast_net_sales",
    "FOP"    => "forecast_operating_income",
    "FOdP"   => "forecast_ordinary_income",
    "FNP"    => "forecast_net_income",
    "FEPS"   => "forecast_eps",
  }.freeze

  # JQUANTS V2 fins/summary → financial_values 固定カラム マッピング（個別）
  JQUANTS_NON_CONSOLIDATED_FIELD_MAP = {
    "NCSales" => :net_sales,
    "NCOP"    => :operating_income,
    "NCOdP"   => :ordinary_income,
    "NCNP"    => :net_income,
    "NCEPS"   => :eps,
    "NCTA"    => :total_assets,
    "NCEq"    => :net_assets,
    "NCBPS"   => :bps,
  }.freeze

  # 整数として扱うカラム
  INTEGER_COLUMNS = %i[
    net_sales operating_income ordinary_income net_income
    total_assets net_assets
    operating_cf investing_cf financing_cf cash_and_equivalents
    shares_outstanding treasury_shares
  ].freeze

  # 小数として扱うカラム
  DECIMAL_COLUMNS = %i[eps diluted_eps equity_ratio bps].freeze

  belongs_to :company
  belongs_to :financial_report, optional: true
  has_one :financial_metric

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  define_json_attributes :data_json, schema: {
    # 配当実績
    dividend_per_share_annual: { type: :decimal },
    total_dividend_paid: { type: :integer },
    payout_ratio: { type: :decimal },
    # 業績予想
    forecast_net_sales: { type: :integer },
    forecast_operating_income: { type: :integer },
    forecast_ordinary_income: { type: :integer },
    forecast_net_income: { type: :integer },
    forecast_eps: { type: :decimal },
    # XBRL追加要素
    cost_of_sales: { type: :integer },
    gross_profit: { type: :integer },
    sga_expenses: { type: :integer },
    current_assets: { type: :integer },
    noncurrent_assets: { type: :integer },
    current_liabilities: { type: :integer },
    noncurrent_liabilities: { type: :integer },
    shareholders_equity: { type: :integer },
  }

  # JQUANTS V2 fins/summary のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1件分のHash
  # @param scope_type [Symbol] :consolidated or :non_consolidated
  # @return [Hash] FinancialValue.create / update に渡せる属性Hash
  def self.get_attributes_from_jquants(data, scope_type:)
    field_map = scope_type == :consolidated ?
      JQUANTS_CONSOLIDATED_FIELD_MAP : JQUANTS_NON_CONSOLIDATED_FIELD_MAP

    attrs = {}
    field_map.each do |jquants_key, column|
      raw_value = data[jquants_key]
      attrs[column] = parse_jquants_value(raw_value, column)
    end

    # 連結のみ data_json を設定
    if scope_type == :consolidated
      json_data = {}
      JQUANTS_CONSOLIDATED_DATA_JSON_MAP.each do |jquants_key, json_key|
        raw_value = data[jquants_key]
        json_data[json_key] = parse_jquants_value_raw(raw_value) if raw_value.present?
      end
      attrs[:data_json] = json_data if json_data.any?
    end

    attrs
  end

  # JQUANTS の文字列値をカラムの型に変換する
  #
  # @param raw_value [String, nil] JQUANTS レスポンスの値（全てString型）
  # @param column [Symbol] カラム名
  # @return [Integer, BigDecimal, nil] 変換後の値
  def self.parse_jquants_value(raw_value, column)
    return nil if raw_value.blank? || raw_value == ""

    if INTEGER_COLUMNS.include?(column)
      raw_value.to_i
    elsif DECIMAL_COLUMNS.include?(column)
      BigDecimal(raw_value)
    else
      raw_value
    end
  rescue ArgumentError
    nil
  end

  # JQUANTS の文字列値を数値に変換する（data_json用、型推定）
  #
  # @param raw_value [String] 元の値
  # @return [Integer, Float, String] 変換後の値
  def self.parse_jquants_value_raw(raw_value)
    return nil if raw_value.blank?

    if raw_value.include?(".")
      raw_value.to_f
    else
      raw_value.to_i
    end
  rescue
    raw_value
  end
end
