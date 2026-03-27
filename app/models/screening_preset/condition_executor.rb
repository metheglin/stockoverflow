class ScreeningPreset::ConditionExecutor
  METRIC_RANGE_FIELDS = %i[
    revenue_yoy operating_income_yoy ordinary_income_yoy net_income_yoy eps_yoy
    roe roa operating_margin ordinary_margin net_margin
    free_cf consecutive_revenue_growth consecutive_profit_growth
  ].freeze

  METRIC_BOOLEAN_FIELDS = %i[
    operating_cf_positive investing_cf_negative free_cf_positive
  ].freeze

  DATA_JSON_RANGE_FIELDS = %i[
    per pbr psr dividend_yield ev_ebitda
    current_ratio debt_to_equity net_debt_to_equity
    asset_turnover gross_margin sga_ratio
    growth_score quality_score value_score composite_score
    revenue_cagr_3y revenue_cagr_5y operating_income_cagr_3y operating_income_cagr_5y
    net_income_cagr_3y net_income_cagr_5y eps_cagr_3y eps_cagr_5y
    payout_ratio dividend_growth_rate consecutive_dividend_growth
    revenue_growth_acceleration operating_income_growth_acceleration
    net_income_growth_acceleration eps_growth_acceleration
  ].freeze

  TREND_FILTER_FIELDS = %i[
    trend_revenue trend_operating_income trend_net_income trend_eps
    trend_operating_margin trend_roe trend_roa trend_free_cf
  ].freeze

  TREND_LABELS = FinancialMetric::TREND_LABELS.freeze

  COMPANY_ATTRIBUTE_FIELDS = %i[
    sector_17_code sector_33_code market_code scale_category
  ].freeze

  ALL_SORTABLE_FIELDS = (METRIC_RANGE_FIELDS + METRIC_BOOLEAN_FIELDS + DATA_JSON_RANGE_FIELDS).freeze

  MAX_PRESET_REF_DEPTH = 3

  attr_reader :conditions_json, :display_json

  def initialize(conditions_json:, display_json: {})
    @conditions_json = normalize_json(conditions_json)
    @display_json = normalize_json(display_json)
  end

  # 検索を実行し、結果を返す
  #
  # @param depth [Integer] preset_ref再帰の深さ（内部利用）
  # @return [Array<Hash>] { company:, metric:, display_values: {} }
  def execute(depth: 0)
    scope = build_base_scope
    scope = apply_conditions(scope, @conditions_json)
    scope = apply_sort_sql(scope)
    scope = apply_limit(scope)

    metrics = scope.includes(:company).to_a
    metrics = apply_post_filters(metrics, @conditions_json, depth: depth)
    metrics = apply_temporal_filters(metrics)
    build_results(metrics)
  end

  # 基本スコープの構築
  def build_base_scope
    scope_type = @conditions_json[:scope_type] || "consolidated"
    period_type = @conditions_json[:period_type] || "annual"

    FinancialMetric
      .where(scope: scope_type, period_type: period_type)
      .latest_period
      .joins(:company)
      .merge(Company.listed)
  end

  # SQLレベルの条件をスコープに適用（再帰的にAND/OR処理）
  def apply_conditions(scope, node)
    conditions = node[:conditions]
    return scope unless conditions.is_a?(Array)

    logic = (node[:logic] || "and").to_s.downcase
    sql_conditions = conditions.filter_map { |cond| build_sql_condition(cond) }
    return scope if sql_conditions.empty?

    if logic == "or"
      combined = sql_conditions.map { |sql, _binds| "(#{sql})" }.join(" OR ")
      all_binds = sql_conditions.flat_map { |_sql, binds| binds }
      scope.where(combined, *all_binds)
    else
      sql_conditions.each do |sql, binds|
        scope = scope.where(sql, *binds)
      end
      scope
    end
  end

  private

  def normalize_json(json)
    case json
    when Hash then json.deep_symbolize_keys
    when String then JSON.parse(json).deep_symbolize_keys
    else {}
    end
  end

  # 個別条件からSQL文字列とバインドパラメータを構築する
  #
  # @return [Array(String, Array), nil] [sql_fragment, bind_values] or nil
  def build_sql_condition(condition)
    if condition[:logic] && condition[:conditions]
      return build_nested_logic_condition(condition)
    end

    type = condition[:type]&.to_s
    case type
    when "metric_range"
      build_metric_range_sql(condition)
    when "metric_boolean"
      build_metric_boolean_sql(condition)
    when "company_attribute"
      build_company_attribute_sql(condition)
    when "trend_filter", "temporal", "turning_point"
      nil # trend_filter, temporal, turning_point はpost_filterで処理
    end
  end

  def build_nested_logic_condition(node)
    conditions = node[:conditions]
    return nil unless conditions.is_a?(Array)

    logic = (node[:logic] || "and").to_s.downcase
    parts = conditions.filter_map { |cond| build_sql_condition(cond) }
    return nil if parts.empty?

    joiner = logic == "or" ? " OR " : " AND "
    combined = parts.map { |sql, _binds| "(#{sql})" }.join(joiner)
    all_binds = parts.flat_map { |_sql, binds| binds }
    [combined, all_binds]
  end

  def build_metric_range_sql(condition)
    field = condition[:field]&.to_sym
    return nil unless METRIC_RANGE_FIELDS.include?(field)

    min_val = condition[:min]
    max_val = condition[:max]
    clauses = []
    binds = []

    if min_val
      clauses << "financial_metrics.#{field} >= ?"
      binds << min_val
    end
    if max_val
      clauses << "financial_metrics.#{field} <= ?"
      binds << max_val
    end

    return nil if clauses.empty?
    [clauses.join(" AND "), binds]
  end

  def build_metric_boolean_sql(condition)
    field = condition[:field]&.to_sym
    return nil unless METRIC_BOOLEAN_FIELDS.include?(field)

    value = condition[:value]
    return nil if value.nil?

    ["financial_metrics.#{field} = ?", [value]]
  end

  def build_company_attribute_sql(condition)
    field = condition[:field]&.to_sym
    return nil unless COMPANY_ATTRIBUTE_FIELDS.include?(field)

    values = condition[:values]
    return nil unless values.is_a?(Array) && values.any?

    placeholders = values.map { "?" }.join(", ")
    ["companies.#{field} IN (#{placeholders})", values]
  end

  def apply_sort_sql(scope)
    sort_by = @display_json[:sort_by]&.to_sym
    sort_order = @display_json[:sort_order]&.to_s&.downcase == "asc" ? "ASC" : "DESC"

    if sort_by && METRIC_RANGE_FIELDS.include?(sort_by)
      scope.order(Arel.sql("financial_metrics.#{sort_by} #{sort_order} NULLS LAST"))
    elsif sort_by && METRIC_BOOLEAN_FIELDS.include?(sort_by)
      scope.order(Arel.sql("financial_metrics.#{sort_by} #{sort_order} NULLS LAST"))
    else
      scope.order(Arel.sql("financial_metrics.fiscal_year_end DESC"))
    end
  end

  def apply_limit(scope)
    limit = @display_json[:limit] || 100
    scope.limit([limit, 500].min)
  end

  # SQLで表現しにくい条件（data_json_range, metric_top_n, preset_ref）はRubyレベルで処理
  def apply_post_filters(metrics, node, depth: 0)
    conditions = node[:conditions]
    return metrics unless conditions.is_a?(Array)

    logic = (node[:logic] || "and").to_s.downcase

    conditions.each do |condition|
      if condition[:logic] && condition[:conditions]
        metrics = apply_nested_post_filter(metrics, condition, depth: depth)
        next
      end

      type = condition[:type]&.to_s
      case type
      when "data_json_range"
        metrics = apply_data_json_range(metrics, condition)
      when "metric_top_n"
        metrics = apply_metric_top_n(metrics, condition)
      when "preset_ref"
        metrics = apply_preset_ref(metrics, condition, logic: logic, depth: depth)
      when "trend_filter"
        metrics = apply_trend_filter(metrics, condition)
      when "turning_point"
        metrics = apply_turning_point_filter(metrics, condition)
      end
    end

    metrics
  end

  def apply_nested_post_filter(metrics, node, depth: 0)
    conditions = node[:conditions]
    return metrics unless conditions.is_a?(Array)

    logic = (node[:logic] || "and").to_s.downcase

    if logic == "or"
      matching_ids = Set.new
      conditions.each do |condition|
        subset = apply_single_post_filter(metrics, condition, depth: depth)
        matching_ids.merge(subset.map(&:id))
      end
      metrics.select { |m| matching_ids.include?(m.id) }
    else
      conditions.each do |condition|
        metrics = apply_single_post_filter(metrics, condition, depth: depth)
      end
      metrics
    end
  end

  def apply_single_post_filter(metrics, condition, depth: 0)
    type = condition[:type]&.to_s
    case type
    when "data_json_range"
      apply_data_json_range(metrics, condition)
    when "metric_top_n"
      apply_metric_top_n(metrics, condition)
    when "preset_ref"
      apply_preset_ref(metrics, condition, logic: "and", depth: depth)
    when "trend_filter"
      apply_trend_filter(metrics, condition)
    when "turning_point"
      apply_turning_point_filter(metrics, condition)
    else
      metrics
    end
  end

  def apply_data_json_range(metrics, condition)
    field = condition[:field]&.to_sym
    return metrics unless DATA_JSON_RANGE_FIELDS.include?(field)

    min_val = condition[:min]
    max_val = condition[:max]
    return metrics unless min_val || max_val

    metrics.select do |m|
      value = m.send(field)
      next false if value.nil?

      value = value.to_f
      next false if min_val && value < min_val.to_f
      next false if max_val && value > max_val.to_f
      true
    end
  end

  def apply_metric_top_n(metrics, condition)
    field = condition[:field]&.to_sym
    all_fields = METRIC_RANGE_FIELDS + DATA_JSON_RANGE_FIELDS
    return metrics unless all_fields.include?(field)

    direction = condition[:direction]&.to_s&.downcase == "asc" ? :asc : :desc
    n = (condition[:n] || 100).to_i

    sortable = metrics.select { |m| m.respond_to?(field) && !m.send(field).nil? }
    sorted = if direction == :asc
               sortable.sort_by { |m| m.send(field).to_f }
             else
               sortable.sort_by { |m| -m.send(field).to_f }
             end
    sorted.first(n)
  end

  def apply_preset_ref(metrics, condition, logic:, depth:)
    return metrics if depth >= MAX_PRESET_REF_DEPTH

    preset_id = condition[:preset_id]
    return metrics unless preset_id

    preset = ScreeningPreset.enabled.find_by(id: preset_id)
    return metrics unless preset

    ref_executor = self.class.new(
      conditions_json: preset.conditions_json,
      display_json: preset.display_json
    )
    ref_results = ref_executor.execute(depth: depth + 1)
    ref_company_ids = ref_results.map { |r| r[:company].id }.to_set

    if logic == "or"
      own_ids = metrics.map(&:company_id).to_set
      combined_ids = own_ids | ref_company_ids
      metrics.select { |m| combined_ids.include?(m.company_id) }
    else
      metrics.select { |m| ref_company_ids.include?(m.company_id) }
    end
  end

  def apply_trend_filter(metrics, condition)
    field = condition[:field]&.to_sym
    return metrics unless TREND_FILTER_FIELDS.include?(field)

    value = condition[:value]&.to_s
    return metrics unless TREND_LABELS.include?(value)

    metrics.select do |m|
      m.respond_to?(field) && m.send(field) == value
    end
  end

  # 転換点フィルタ: TrendTurningPointテーブルをJOINして条件適用
  #
  # 条件例:
  # { "type": "turning_point", "pattern_type": "growth_resumption", "significance": "high", "since_months": 12 }
  def apply_turning_point_filter(metrics, condition)
    pattern_type = condition[:pattern_type]
    return metrics if pattern_type.blank?

    company_ids = metrics.map(&:company_id)
    scope = TrendTurningPoint.where(company_id: company_ids)
    scope = scope.where(pattern_type: pattern_type)

    if condition[:significance].present?
      scope = scope.where(significance: condition[:significance])
    end

    if condition[:since_months].present?
      since_date = Date.current - condition[:since_months].to_i.months
      scope = scope.where("fiscal_year_end >= ?", since_date)
    end

    matching_company_ids = scope.distinct.pluck(:company_id).to_set
    metrics.select { |m| matching_company_ids.include?(m.company_id) }
  end

  # temporal条件をconditions_jsonから収集し、MultiPeriodConditionEvaluatorで適用
  def apply_temporal_filters(metrics)
    temporal_conditions = collect_temporal_conditions(@conditions_json)
    return metrics if temporal_conditions.empty?

    company_ids = metrics.map(&:company_id)
    scope_type = @conditions_json[:scope_type] || "consolidated"
    period_type = @conditions_json[:period_type] || "annual"

    evaluator = ScreeningPreset::MultiPeriodConditionEvaluator.new(
      company_ids: company_ids,
      conditions: temporal_conditions,
      scope_type: scope_type,
      period_type: period_type
    )
    passing_ids = evaluator.execute.to_set
    metrics.select { |m| passing_ids.include?(m.company_id) }
  end

  # conditions_json内のtemporal条件を再帰的に収集する
  def collect_temporal_conditions(node)
    conditions = node[:conditions]
    return [] unless conditions.is_a?(Array)

    conditions.flat_map do |condition|
      if condition[:logic] && condition[:conditions]
        collect_temporal_conditions(condition)
      elsif condition[:type]&.to_s == "temporal"
        [condition]
      else
        []
      end
    end
  end

  def build_results(metrics)
    metrics.map do |metric|
      {
        company: metric.company,
        metric: metric,
      }
    end
  end
end
