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

  # フィルタ可能な指標（トレンド分類）のオプション一覧を返す
  def trend_filter_options
    fields = ScreeningPreset::ConditionExecutor::TREND_FILTER_FIELDS
    fields.map { |f| [I18n.t("metrics.#{f}", locale: :ja, default: f.to_s), f.to_s] }
  end

  # トレンドラベルの選択肢を返す
  def trend_label_options
    ScreeningPreset::ConditionExecutor::TREND_LABELS.map do |label|
      [I18n.t("trend_labels.#{label}", locale: :ja, default: label), label]
    end
  end

  # 全フィルタ条件タイプのオプション一覧を返す
  def condition_type_options
    [
      [I18n.t("condition_types.metric_range", locale: :ja), "metric_range"],
      [I18n.t("condition_types.data_json_range", locale: :ja), "data_json_range"],
      [I18n.t("condition_types.metric_boolean", locale: :ja), "metric_boolean"],
      [I18n.t("condition_types.company_attribute", locale: :ja), "company_attribute"],
      [I18n.t("condition_types.trend_filter", locale: :ja), "trend_filter"],
      [I18n.t("condition_types.temporal", locale: :ja, default: "時間軸条件"), "temporal"],
    ]
  end

  # 時間軸条件の種別オプション一覧を返す
  def temporal_type_options
    [
      ["N期中M期達成", "at_least_n_of_m"],
      ["N期連続改善", "improving"],
      ["N期連続悪化", "deteriorating"],
      ["プラス転換", "transition_positive"],
      ["マイナス転換", "transition_negative"],
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

  TREND_BADGE_CONFIG = {
    "improving" => { css: "badge-trend-improving", icon: "\u2191", label: "改善" },
    "deteriorating" => { css: "badge-trend-deteriorating", icon: "\u2193", label: "悪化" },
    "stable" => { css: "badge-trend-stable", icon: "\u2192", label: "安定" },
    "turning_up" => { css: "badge-trend-turning-up", icon: "\u2191", label: "転換" },
    "turning_down" => { css: "badge-trend-turning-down", icon: "\u2193", label: "転換" },
    "volatile" => { css: "badge-trend-volatile", icon: "\u223C", label: "変動" },
  }.freeze

  ACCELERATION_CONSISTENCY_LABELS = {
    "accelerating" => "加速中",
    "decelerating" => "減速中",
    "mixed" => "混在",
  }.freeze

  # トレンドラベルに対応するバッジHTMLを生成する
  #
  # @param trend_label [String, nil] トレンドラベル（"improving", "deteriorating"等）
  # @return [String] バッジのHTML。ラベルがnilの場合は空文字列
  def trend_badge(trend_label)
    config = TREND_BADGE_CONFIG[trend_label.to_s]
    return "" unless config

    tag.span(class: "badge #{config[:css]}") do
      "#{config[:icon]} #{config[:label]}".html_safe
    end
  end

  # 成長加速度の一貫性ラベルを返す
  #
  # @param consistency [String, nil] "accelerating" | "decelerating" | "mixed"
  # @return [String] 日本語ラベル
  def acceleration_consistency_label(consistency)
    ACCELERATION_CONSISTENCY_LABELS[consistency.to_s] || "-"
  end

  # 成長加速度の値をフォーマットする（パーセントポイント表示）
  #
  # @param value [Numeric, nil] 加速度の値（小数）
  # @return [String] フォーマット済み文字列（例: "+5.0pp"）
  def format_acceleration(value)
    return "-" if value.nil?
    pp_value = (value.to_f * 100).round(1)
    pp_value >= 0 ? "+#{pp_value}pp" : "#{pp_value}pp"
  end

  # 金額を読みやすい形式にフォーマット
  #
  # 100_000_000 => "1.00億"
  # 1_000_000_000_000 => "1.00兆"
  def format_amount(value)
    return "-" if value.nil?
    if value.to_f.abs >= 1_000_000_000_000
      "#{(value.to_f / 1_000_000_000_000).round(2)}兆"
    elsif value.to_f.abs >= 100_000_000
      "#{(value.to_f / 100_000_000).round(2)}億"
    elsif value.to_f.abs >= 10_000
      "#{(value.to_f / 10_000).round(1)}万"
    else
      number_with_delimiter(value.to_i)
    end
  end

  # パーセント表示（企業詳細用）
  def format_detail_percent(value)
    return "-" if value.nil?
    "#{(value.to_f * 100).round(1)}%"
  end

  # 倍率表示（企業詳細用）
  def format_detail_ratio(value)
    return "-" if value.nil?
    "#{value.to_f.round(2)}x"
  end

  # YoY表示（符号付き）
  def format_yoy(value)
    return "-" if value.nil?
    pct = (value.to_f * 100).round(1)
    pct >= 0 ? "+#{pct}% YoY" : "#{pct}% YoY"
  end

  # テーブル内の値フォーマット
  def format_table_value(value, format_type)
    return "-" if value.nil?
    case format_type
    when :amount
      format_amount(value)
    when :percent, :yoy
      format_detail_percent(value)
    when :ratio
      format_detail_ratio(value)
    when :number
      if value.is_a?(Integer) || value.to_f == value.to_i.to_f
        number_with_delimiter(value.to_i)
      else
        value.to_f.round(2).to_s
      end
    else
      value.to_s
    end
  end

  # イベントのseverityラベルを返す
  #
  # @param severity [String] "info", "notable", "critical"
  # @return [String] 日本語ラベル
  EVENT_SEVERITY_LABELS = {
    "info" => "情報",
    "notable" => "注目",
    "critical" => "重要",
  }.freeze

  def event_severity_label(severity)
    EVENT_SEVERITY_LABELS[severity.to_s] || severity.to_s
  end

  # 転換点パターンタイプのラベルを返す
  #
  # @param pattern_type [String]
  # @return [String] 日本語ラベル
  TURNING_POINT_PATTERN_LABELS = {
    "growth_resumption" => "増収転換",
    "margin_bottom_reversal" => "利益率底打ち",
    "free_cf_turnaround" => "FCF黒字化",
    "roe_reversal" => "ROE反転",
    "revenue_growth_acceleration" => "成長加速",
    "valuation_shift" => "バリュエーション変動",
  }.freeze

  def turning_point_pattern_label(pattern_type)
    TURNING_POINT_PATTERN_LABELS[pattern_type.to_s] || pattern_type.to_s.humanize
  end

  # 転換点のsignificanceラベルを返す
  #
  # @param significance [String]
  # @return [String] 日本語ラベル
  TURNING_POINT_SIGNIFICANCE_LABELS = {
    "low" => "低",
    "medium" => "中",
    "high" => "高",
  }.freeze

  def turning_point_significance_label(significance)
    TURNING_POINT_SIGNIFICANCE_LABELS[significance.to_s] || significance.to_s
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
