module DashboardHelper
  PERCENT_FIELDS = %i[
    revenue_yoy operating_income_yoy ordinary_income_yoy net_income_yoy eps_yoy
    roe roa operating_margin ordinary_margin net_margin
    gross_margin sga_ratio dividend_yield payout_ratio dividend_growth_rate
    revenue_cagr_3y revenue_cagr_5y operating_income_cagr_3y operating_income_cagr_5y
    net_income_cagr_3y net_income_cagr_5y eps_cagr_3y eps_cagr_5y
    asset_turnover current_ratio debt_to_equity net_debt_to_equity
  ].freeze

  SCORE_FIELDS = %i[
    growth_score quality_score value_score composite_score
  ].freeze

  INTEGER_FIELDS = %i[
    consecutive_revenue_growth consecutive_profit_growth consecutive_dividend_growth
  ].freeze

  CURRENCY_FIELDS = %i[
    free_cf
  ].freeze

  RATIO_FIELDS = %i[
    per pbr psr ev_ebitda
  ].freeze

  # 指標値を適切にフォーマットする
  #
  # @param value [Numeric, nil] 値
  # @param field [Symbol, String] フィールド名
  # @return [String] フォーマット済み文字列
  def format_metric_value(value, field)
    return "-" if value.nil?

    field = field.to_sym
    if PERCENT_FIELDS.include?(field)
      format_as_percent(value)
    elsif SCORE_FIELDS.include?(field)
      format_as_score(value)
    elsif INTEGER_FIELDS.include?(field)
      value.to_i.to_s
    elsif CURRENCY_FIELDS.include?(field)
      format_as_currency(value)
    elsif RATIO_FIELDS.include?(field)
      format_as_ratio(value)
    else
      format_as_number(value)
    end
  end

  # 増減に応じたCSSクラスを返す
  def value_color_class(value)
    return "" if value.nil?
    value.to_f >= 0 ? "value-positive" : "value-negative"
  end

  # フィルタ可能な指標（数値）のオプション一覧を返す
  def metric_range_filter_options
    fields = ScreeningPreset::ConditionExecutor::METRIC_RANGE_FIELDS
    fields.map { |f| [I18n.t("metrics.#{f}", locale: :ja, default: f.to_s), f.to_s] }
  end

  # フィルタ可能な指標（詳細・JSON）のオプション一覧を返す
  def data_json_range_filter_options
    fields = ScreeningPreset::ConditionExecutor::DATA_JSON_RANGE_FIELDS
    fields.map { |f| [I18n.t("metrics.#{f}", locale: :ja, default: f.to_s), f.to_s] }
  end

  # フィルタ可能な指標（ブーリアン）のオプション一覧を返す
  def metric_boolean_filter_options
    fields = ScreeningPreset::ConditionExecutor::METRIC_BOOLEAN_FIELDS
    fields.map { |f| [I18n.t("metrics.#{f}", locale: :ja, default: f.to_s), f.to_s] }
  end

  # 企業属性のフィルタオプション一覧を返す
  def company_attribute_filter_options
    fields = ScreeningPreset::ConditionExecutor::COMPANY_ATTRIBUTE_FIELDS
    fields.map { |f| [I18n.t("company_attributes.#{f}", locale: :ja, default: f.to_s), f.to_s] }
  end

  # 全フィルタ条件タイプのオプション一覧を返す
  def condition_type_options
    [
      [I18n.t("condition_types.metric_range", locale: :ja), "metric_range"],
      [I18n.t("condition_types.data_json_range", locale: :ja), "data_json_range"],
      [I18n.t("condition_types.metric_boolean", locale: :ja), "metric_boolean"],
      [I18n.t("condition_types.company_attribute", locale: :ja), "company_attribute"],
    ]
  end

  # 表示カラムのラベルを返す
  def column_label(column)
    case column.to_s
    when "securities_code"
      "証券コード"
    when "name"
      "社名"
    when "sector_33_name"
      "セクター"
    when "market_name"
      "市場区分"
    else
      I18n.t("metrics.#{column}", locale: :ja, default: column.to_s.titleize)
    end
  end

  # カラムが数値系かどうか判定
  def numeric_column?(column)
    col = column.to_sym
    %i[securities_code name sector_33_name market_name].exclude?(col)
  end

  COMPANY_COLUMNS = %w[securities_code name sector_33_name market_name].freeze

  # 結果行からカラムの値を取得する
  #
  # @param company [Company] 企業レコード
  # @param metric [FinancialMetric] 指標レコード
  # @param column [String] カラム名
  # @return [Object] カラムの値
  def get_result_value(company, metric, column)
    col = column.to_s
    if COMPANY_COLUMNS.include?(col)
      company.send(col)
    elsif metric.respond_to?(col)
      metric.send(col)
    end
  end

  private

  def format_as_percent(value)
    "#{(value.to_f * 100).round(1)}%"
  end

  def format_as_score(value)
    value.to_f.round(1).to_s
  end

  def format_as_currency(value)
    number_to_currency(value.to_f / 1_000_000, unit: "", precision: 0, delimiter: ",") + "百万"
  end

  def format_as_ratio(value)
    value.to_f.round(2).to_s
  end

  def format_as_number(value)
    if value.is_a?(Integer) || value.to_f == value.to_i.to_f
      number_with_delimiter(value.to_i)
    else
      value.to_f.round(2).to_s
    end
  end
end
