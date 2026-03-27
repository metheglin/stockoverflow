class FinancialEvent < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_metric

  enum :event_type, {
    streak_started: 0,
    streak_broken: 1,
    streak_milestone: 2,
    fcf_turned_positive: 3,
    fcf_turned_negative: 4,
    margin_expansion: 5,
    margin_contraction: 6,
    roe_crossed_threshold: 7,
    extreme_growth: 8,
    extreme_decline: 9,
    growth_acceleration: 10,
    growth_deceleration: 11,
  }

  enum :severity, {
    info: 0,
    notable: 1,
    critical: 2,
  }

  define_json_attributes :data_json, schema: {
    description: { type: :string },
    metric_name: { type: :string },
    value: { type: :decimal },
    previous_value: { type: :decimal },
    threshold: { type: :decimal },
    streak_count: { type: :integer },
  }

  # 閾値定数
  EXTREME_GROWTH_THRESHOLD = 0.5
  EXTREME_DECLINE_THRESHOLD = -0.3
  MARGIN_EXPANSION_THRESHOLD = 0.03
  MARGIN_CONTRACTION_THRESHOLD = -0.03
  ROE_THRESHOLD = 0.15
  STREAK_MILESTONE_PERIODS = [3, 5, 10].freeze

  # 2つのFinancialMetricから財務イベントを検出する
  #
  # @param current_metric [FinancialMetric] 当期の指標
  # @param previous_metric [FinancialMetric, nil] 前期の指標
  # @return [Array<Hash>] 検出されたイベントの属性Hash配列
  #
  # 例:
  #   events = FinancialEvent.detect_events(current_metric, previous_metric)
  #   # => [{ event_type: :streak_started, severity: :notable, ... }, ...]
  #
  def self.detect_events(current_metric, previous_metric)
    events = []
    events.concat(detect_streak_events(current_metric, previous_metric))
    events.concat(detect_fcf_events(current_metric, previous_metric))
    events.concat(detect_margin_events(current_metric, previous_metric))
    events.concat(detect_roe_events(current_metric, previous_metric))
    events.concat(detect_extreme_growth_events(current_metric))
    events.concat(detect_acceleration_events(current_metric, previous_metric))
    events
  end

  # 連続増収増益に関するイベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @return [Array<Hash>]
  def self.detect_streak_events(current_metric, previous_metric)
    events = []
    prev_revenue_streak = previous_metric&.consecutive_revenue_growth || 0
    current_revenue_streak = current_metric.consecutive_revenue_growth || 0

    # streak_started: 0→1に転換
    if prev_revenue_streak == 0 && current_revenue_streak >= 1
      events << build_event(:streak_started, :info, current_metric,
        description: "増収に転換",
        metric_name: "consecutive_revenue_growth",
        value: current_revenue_streak)
    end

    # streak_broken: 1以上→0に転換（特に長期連続の途切れは重要）
    if prev_revenue_streak >= 1 && current_revenue_streak == 0
      severity = prev_revenue_streak >= 3 ? :critical : :notable
      events << build_event(:streak_broken, severity, current_metric,
        description: "#{prev_revenue_streak}期連続増収がストップ",
        metric_name: "consecutive_revenue_growth",
        value: 0,
        previous_value: prev_revenue_streak)
    end

    # streak_milestone: 特定期数に到達
    if STREAK_MILESTONE_PERIODS.include?(current_revenue_streak)
      severity = current_revenue_streak >= 5 ? :critical : :notable
      events << build_event(:streak_milestone, severity, current_metric,
        description: "#{current_revenue_streak}期連続増収を達成",
        metric_name: "consecutive_revenue_growth",
        streak_count: current_revenue_streak)
    end

    events
  end

  # FCF（フリーキャッシュフロー）の正負転換イベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @return [Array<Hash>]
  def self.detect_fcf_events(current_metric, previous_metric)
    return [] unless previous_metric
    return [] if current_metric.free_cf_positive.nil? || previous_metric.free_cf_positive.nil?

    events = []

    if current_metric.free_cf_positive && !previous_metric.free_cf_positive
      events << build_event(:fcf_turned_positive, :notable, current_metric,
        description: "フリーCFが黒字に転換",
        metric_name: "free_cf",
        value: current_metric.free_cf)
    end

    if !current_metric.free_cf_positive && previous_metric.free_cf_positive
      events << build_event(:fcf_turned_negative, :notable, current_metric,
        description: "フリーCFが赤字に転落",
        metric_name: "free_cf",
        value: current_metric.free_cf)
    end

    events
  end

  # 営業利益率の拡大・縮小イベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @return [Array<Hash>]
  def self.detect_margin_events(current_metric, previous_metric)
    return [] unless previous_metric
    return [] if current_metric.operating_margin.nil? || previous_metric.operating_margin.nil?

    events = []
    diff = current_metric.operating_margin.to_f - previous_metric.operating_margin.to_f

    if diff >= MARGIN_EXPANSION_THRESHOLD
      severity = diff >= 0.05 ? :critical : :notable
      events << build_event(:margin_expansion, severity, current_metric,
        description: "営業利益率が#{(diff * 100).round(1)}pt改善",
        metric_name: "operating_margin",
        value: current_metric.operating_margin.to_f,
        previous_value: previous_metric.operating_margin.to_f)
    end

    if diff <= MARGIN_CONTRACTION_THRESHOLD
      severity = diff <= -0.05 ? :critical : :notable
      events << build_event(:margin_contraction, severity, current_metric,
        description: "営業利益率が#{(diff.abs * 100).round(1)}pt悪化",
        metric_name: "operating_margin",
        value: current_metric.operating_margin.to_f,
        previous_value: previous_metric.operating_margin.to_f)
    end

    events
  end

  # ROE閾値超えイベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @return [Array<Hash>]
  def self.detect_roe_events(current_metric, previous_metric)
    return [] unless previous_metric
    return [] if current_metric.roe.nil? || previous_metric.roe.nil?

    events = []

    if current_metric.roe.to_f >= ROE_THRESHOLD && previous_metric.roe.to_f < ROE_THRESHOLD
      events << build_event(:roe_crossed_threshold, :notable, current_metric,
        description: "ROEが#{(ROE_THRESHOLD * 100).round(0)}%を突破",
        metric_name: "roe",
        value: current_metric.roe.to_f,
        threshold: ROE_THRESHOLD)
    end

    events
  end

  # 極端な成長・衰退イベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @return [Array<Hash>]
  def self.detect_extreme_growth_events(current_metric)
    events = []

    if current_metric.revenue_yoy.present? && current_metric.revenue_yoy.to_f >= EXTREME_GROWTH_THRESHOLD
      events << build_event(:extreme_growth, :critical, current_metric,
        description: "売上高が#{(current_metric.revenue_yoy.to_f * 100).round(1)}%の急成長",
        metric_name: "revenue_yoy",
        value: current_metric.revenue_yoy.to_f)
    end

    if current_metric.revenue_yoy.present? && current_metric.revenue_yoy.to_f <= EXTREME_DECLINE_THRESHOLD
      events << build_event(:extreme_decline, :critical, current_metric,
        description: "売上高が#{(current_metric.revenue_yoy.to_f.abs * 100).round(1)}%の急減",
        metric_name: "revenue_yoy",
        value: current_metric.revenue_yoy.to_f)
    end

    events
  end

  # 成長加速・減速イベントを検出する
  #
  # @param current_metric [FinancialMetric]
  # @param previous_metric [FinancialMetric, nil]
  # @return [Array<Hash>]
  def self.detect_acceleration_events(current_metric, previous_metric)
    return [] unless previous_metric

    events = []
    acceleration = current_metric.revenue_growth_acceleration
    prev_acceleration = previous_metric.revenue_growth_acceleration

    return events if acceleration.nil? || prev_acceleration.nil?

    # 減速→加速に転換
    if acceleration.to_f > 0 && prev_acceleration.to_f <= 0
      events << build_event(:growth_acceleration, :notable, current_metric,
        description: "売上成長率が加速に転換",
        metric_name: "revenue_growth_acceleration",
        value: acceleration.to_f,
        previous_value: prev_acceleration.to_f)
    end

    # 加速→減速に転換
    if acceleration.to_f < 0 && prev_acceleration.to_f >= 0
      events << build_event(:growth_deceleration, :info, current_metric,
        description: "売上成長率が減速に転換",
        metric_name: "revenue_growth_acceleration",
        value: acceleration.to_f,
        previous_value: prev_acceleration.to_f)
    end

    events
  end

  # イベント属性Hashを構築するヘルパー
  #
  # @param event_type [Symbol]
  # @param severity [Symbol]
  # @param metric [FinancialMetric]
  # @param data [Hash] data_jsonに格納する追加データ
  # @return [Hash]
  def self.build_event(event_type, severity, metric, **data)
    {
      company_id: metric.company_id,
      financial_metric_id: metric.id,
      event_type: event_type,
      severity: severity,
      fiscal_year_end: metric.fiscal_year_end,
      data_json: data.compact,
    }
  end
end
