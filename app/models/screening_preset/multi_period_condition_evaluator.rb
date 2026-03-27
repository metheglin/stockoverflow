class ScreeningPreset::MultiPeriodConditionEvaluator
  TEMPORAL_TYPES = %w[
    at_least_n_of_m
    consecutive
    improving
    deteriorating
    transition_positive
    transition_negative
  ].freeze

  METRIC_FIELDS = %w[
    roe roa operating_margin net_margin
    revenue_yoy operating_income_yoy net_income_yoy eps_yoy
  ].freeze

  BOOLEAN_FIELDS = %w[
    free_cf_positive operating_cf_positive
  ].freeze

  COMPARISON_OPERATORS = {
    "gte" => :>=,
    "lte" => :<=,
    "gt" => :>,
    "lt" => :<,
  }.freeze

  attr_reader :company_ids, :conditions, :scope_type, :period_type

  # @param company_ids [Array<Integer>] 対象企業ID（事前フィルタ済み）
  # @param conditions [Array<Hash>] 時間軸条件の配列
  # @param scope_type [String] "consolidated" or "non_consolidated"
  # @param period_type [String] "annual" etc.
  def initialize(company_ids:, conditions:, scope_type: "consolidated", period_type: "annual")
    @company_ids = company_ids
    @conditions = normalize_conditions(conditions)
    @scope_type = scope_type
    @period_type = period_type
  end

  # 全条件を満たす企業IDの配列を返す
  # @return [Array<Integer>]
  def execute
    return [] if @company_ids.empty? || @conditions.empty?

    histories = load_metrics_histories
    @company_ids.select do |company_id|
      metrics_history = histories[company_id] || []
      @conditions.all? { |condition| evaluate_temporal_condition(metrics_history, condition) }
    end
  end

  # 企業の履歴データが時間軸条件を満たすか判定
  #
  # @param metrics_history [Array<FinancialMetric>] fiscal_year_end昇順
  # @param condition [Hash] 時間軸条件
  # @return [Boolean]
  def evaluate_temporal_condition(metrics_history, condition)
    temporal_type = condition[:temporal_type].to_s
    return false unless TEMPORAL_TYPES.include?(temporal_type)

    case temporal_type
    when "at_least_n_of_m"
      evaluate_at_least_n_of_m(metrics_history, condition)
    when "consecutive"
      evaluate_consecutive(metrics_history, condition)
    when "improving"
      evaluate_direction(metrics_history, condition, :improving)
    when "deteriorating"
      evaluate_direction(metrics_history, condition, :deteriorating)
    when "transition_positive"
      evaluate_transition(metrics_history, condition, from: false, to: true)
    when "transition_negative"
      evaluate_transition(metrics_history, condition, from: true, to: false)
    else
      false
    end
  end

  private

  def normalize_conditions(conditions)
    conditions.map do |c|
      c.is_a?(Hash) ? c.deep_symbolize_keys : {}
    end
  end

  # 対象企業の履歴データをバッチロードする
  #
  # @return [Hash<Integer, Array<FinancialMetric>>] company_id => metrics(fiscal_year_end昇順)
  def load_metrics_histories
    FinancialMetric
      .where(company_id: @company_ids, scope: @scope_type, period_type: @period_type)
      .order(:company_id, :fiscal_year_end)
      .group_by(&:company_id)
  end

  # 直近M期中N期以上の条件を評価
  def evaluate_at_least_n_of_m(metrics_history, condition)
    field = condition[:field].to_s
    return false unless valid_metric_field?(field)

    n = condition[:n].to_i
    m = condition[:m].to_i
    threshold = condition[:threshold].to_f
    comparison = condition[:comparison]&.to_s || "gte"
    operator = COMPARISON_OPERATORS[comparison] || :>=

    return false if m <= 0 || n <= 0 || n > m

    recent = metrics_history.last(m)
    return false if recent.size < m

    count = recent.count do |metric|
      value = get_field_value(metric, field)
      next false if value.nil?
      value.to_f.send(operator, threshold)
    end

    count >= n
  end

  # N期連続の方向性条件を評価
  def evaluate_consecutive(metrics_history, condition)
    direction = condition[:direction]&.to_s
    case direction
    when "improving"
      evaluate_direction(metrics_history, condition, :improving)
    when "deteriorating"
      evaluate_direction(metrics_history, condition, :deteriorating)
    else
      false
    end
  end

  # 直近N期分で連続改善/悪化を評価
  #
  # N期連続改善 = 直近N+1期分のデータが必要（N回の差分を見る）
  def evaluate_direction(metrics_history, condition, direction)
    field = condition[:field].to_s
    return false unless valid_metric_field?(field)

    n = condition[:n].to_i
    return false if n <= 0

    # N期連続の変化を見るにはN+1個のデータポイントが必要
    required = n + 1
    recent = metrics_history.last(required)
    return false if recent.size < required

    values = recent.map { |m| get_field_value(m, field) }
    return false if values.any?(&:nil?)

    float_values = values.map(&:to_f)
    consecutive_pairs = float_values.each_cons(2).to_a

    if direction == :improving
      consecutive_pairs.all? { |prev, curr| curr > prev }
    else
      consecutive_pairs.all? { |prev, curr| curr < prev }
    end
  end

  # ブーリアンフィールドの転換を評価（前期→当期）
  def evaluate_transition(metrics_history, condition, from:, to:)
    field = condition[:field].to_s
    return false unless valid_boolean_field?(field)
    return false if metrics_history.size < 2

    current = metrics_history[-1]
    previous = metrics_history[-2]

    current_value = get_field_value(current, field)
    previous_value = get_field_value(previous, field)

    return false if current_value.nil? || previous_value.nil?

    to_bool(previous_value) == from && to_bool(current_value) == to
  end

  def valid_metric_field?(field)
    METRIC_FIELDS.include?(field)
  end

  def valid_boolean_field?(field)
    BOOLEAN_FIELDS.include?(field)
  end

  def get_field_value(metric, field)
    return nil unless metric.respond_to?(field)
    metric.send(field)
  end

  def to_bool(value)
    return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
