class TrendTurningPoint < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_metric

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

  enum :pattern_type, {
    growth_resumption: 0,
    margin_bottom_reversal: 1,
    free_cf_turnaround: 2,
    roe_reversal: 3,
    revenue_growth_acceleration: 4,
    valuation_shift: 5,
  }

  enum :significance, {
    low: 0,
    medium: 1,
    high: 2,
  }

  define_json_attributes :data_json, schema: {
    description: { type: :string },
    metric_name: { type: :string },
    value: { type: :decimal },
    previous_value: { type: :decimal },
    decline_count: { type: :integer },
    sector_median: { type: :decimal },
  }

  # 転換点を一括検出する
  #
  # 過去メトリクス履歴を参照して全6パターンの転換点を検出する。
  #
  # @param current_metric [FinancialMetric] 当期指標
  # @param metric_history [Array<FinancialMetric>] 過去のメトリクス(fiscal_year_end降順、最大5期分)
  # @param sector_stats [Hash, nil] セクター統計 (SectorMetric.data_json)
  # @return [Array<Hash>] 検出された転換点の属性Hash配列
  def self.detect_all(current_metric, metric_history, sector_stats: nil)
    return [] if metric_history.empty?

    turning_points = []
    turning_points.concat(detect_growth_resumption(current_metric, metric_history))
    turning_points.concat(detect_free_cf_turnaround(current_metric, metric_history))
    turning_points.concat(detect_margin_bottom_reversal(current_metric, metric_history))
    turning_points.concat(detect_roe_reversal(current_metric, metric_history))
    turning_points.concat(detect_revenue_growth_acceleration(current_metric, metric_history))
    turning_points.concat(detect_valuation_shift(current_metric, sector_stats))
    turning_points
  end

  # P1: growth_resumption - 増収増益の開始
  #
  # consecutive_revenue_growth が 0→1 に転換（前期まで0だった状態から増収開始）
  #
  # @param current_metric [FinancialMetric]
  # @param metric_history [Array<FinancialMetric>] fiscal_year_end降順
  # @return [Array<Hash>]
  def self.detect_growth_resumption(current_metric, metric_history)
    current_streak = current_metric.consecutive_revenue_growth || 0
    return [] unless current_streak >= 1

    prev_metric = metric_history.first
    return [] unless prev_metric
    prev_streak = prev_metric.consecutive_revenue_growth || 0
    return [] unless prev_streak == 0

    decline_count = get_consecutive_decline_count(metric_history, :revenue_yoy)
    significance = decline_count >= 2 ? :high : :medium

    [build_turning_point(:growth_resumption, significance, current_metric,
      description: "#{decline_count > 0 ? "#{decline_count}期の減収後に" : ""}増収に転換",
      metric_name: "consecutive_revenue_growth",
      value: current_streak,
      decline_count: decline_count)]
  end

  # P2: free_cf_turnaround - フリーCF黒字転換
  #
  # free_cf_positive が false→true に転換
  #
  # @param current_metric [FinancialMetric]
  # @param metric_history [Array<FinancialMetric>]
  # @return [Array<Hash>]
  def self.detect_free_cf_turnaround(current_metric, metric_history)
    return [] unless current_metric.free_cf_positive == true

    prev_metric = metric_history.first
    return [] unless prev_metric
    return [] unless prev_metric.free_cf_positive == false

    negative_count = get_consecutive_decline_count(metric_history, :free_cf_positive, boolean_false: true)
    significance = negative_count >= 2 ? :high : :medium

    [build_turning_point(:free_cf_turnaround, significance, current_metric,
      description: "フリーCFが黒字に転換",
      metric_name: "free_cf",
      value: current_metric.free_cf)]
  end

  # P3: margin_bottom_reversal - 営業利益率の底打ち反転
  #
  # 営業利益率が2期以上下落した後に反転上昇
  #
  # @param current_metric [FinancialMetric]
  # @param metric_history [Array<FinancialMetric>]
  # @return [Array<Hash>]
  def self.detect_margin_bottom_reversal(current_metric, metric_history)
    return [] if current_metric.operating_margin.nil?
    return [] if metric_history.size < 2

    prev = metric_history[0]
    prev2 = metric_history[1]
    return [] if prev&.operating_margin.nil? || prev2&.operating_margin.nil?

    # 当期 > 前期（反転上昇）かつ 前期 < 前々期（それまで下落していた）
    current_margin = current_metric.operating_margin.to_f
    prev_margin = prev.operating_margin.to_f
    prev2_margin = prev2.operating_margin.to_f

    return [] unless current_margin > prev_margin && prev_margin < prev2_margin

    decline_count = get_consecutive_decline_count(metric_history, :operating_margin, direction: :decreasing)
    significance = decline_count >= 3 ? :high : :medium

    [build_turning_point(:margin_bottom_reversal, significance, current_metric,
      description: "営業利益率が底打ち反転（#{(current_margin * 100).round(1)}%）",
      metric_name: "operating_margin",
      value: current_margin,
      previous_value: prev_margin,
      decline_count: decline_count)]
  end

  # P4: roe_reversal - ROE反転上昇
  #
  # ROEが下落した後に反転上昇
  #
  # @param current_metric [FinancialMetric]
  # @param metric_history [Array<FinancialMetric>]
  # @return [Array<Hash>]
  def self.detect_roe_reversal(current_metric, metric_history)
    return [] if current_metric.roe.nil?
    return [] if metric_history.size < 2

    prev = metric_history[0]
    prev2 = metric_history[1]
    return [] if prev&.roe.nil? || prev2&.roe.nil?

    current_roe = current_metric.roe.to_f
    prev_roe = prev.roe.to_f
    prev2_roe = prev2.roe.to_f

    return [] unless current_roe > prev_roe && prev_roe < prev2_roe

    decline_count = get_consecutive_decline_count(metric_history, :roe, direction: :decreasing)
    significance = decline_count >= 2 ? :high : :medium

    [build_turning_point(:roe_reversal, significance, current_metric,
      description: "ROEが反転上昇（#{(current_roe * 100).round(1)}%）",
      metric_name: "roe",
      value: current_roe,
      previous_value: prev_roe,
      decline_count: decline_count)]
  end

  # P5: revenue_growth_acceleration - 売上成長率の加速
  #
  # 売上YoYが前期を上回り加速
  #
  # @param current_metric [FinancialMetric]
  # @param metric_history [Array<FinancialMetric>]
  # @return [Array<Hash>]
  def self.detect_revenue_growth_acceleration(current_metric, metric_history)
    return [] if current_metric.revenue_yoy.nil?

    prev = metric_history.first
    return [] unless prev
    return [] if prev.revenue_yoy.nil?

    current_yoy = current_metric.revenue_yoy.to_f
    prev_yoy = prev.revenue_yoy.to_f

    # 成長が加速（YoYが前期より大きい）かつ両方プラス成長
    return [] unless current_yoy > prev_yoy && current_yoy > 0 && prev_yoy >= 0

    significance = (current_yoy - prev_yoy) >= 0.1 ? :high : :medium

    [build_turning_point(:revenue_growth_acceleration, significance, current_metric,
      description: "売上成長率が加速（#{(current_yoy * 100).round(1)}% ← #{(prev_yoy * 100).round(1)}%）",
      metric_name: "revenue_yoy",
      value: current_yoy,
      previous_value: prev_yoy)]
  end

  # P6: valuation_shift - バリュエーション急変
  #
  # PERがセクター中央値から大きく乖離している場合
  #
  # @param current_metric [FinancialMetric]
  # @param sector_stats [Hash, nil]
  # @return [Array<Hash>]
  def self.detect_valuation_shift(current_metric, sector_stats)
    return [] unless sector_stats
    per = current_metric.per
    return [] if per.nil?

    per_stats = sector_stats["per"]
    return [] unless per_stats.is_a?(Hash)

    median = per_stats["median"]
    return [] if median.nil? || median.to_f <= 0

    per_value = per.to_f
    ratio = per_value / median.to_f

    # セクター中央値の半分以下 or 2倍以上
    return [] unless ratio <= 0.5 || ratio >= 2.0

    if ratio <= 0.5
      significance = ratio <= 0.3 ? :high : :medium
      desc = "PERがセクター中央値の#{(ratio * 100).round(0)}%と割安"
    else
      significance = ratio >= 3.0 ? :high : :medium
      desc = "PERがセクター中央値の#{(ratio * 100).round(0)}%と割高"
    end

    [build_turning_point(:valuation_shift, significance, current_metric,
      description: desc,
      metric_name: "per",
      value: per_value,
      sector_median: median.to_f)]
  end

  # 連続した下落期数を数える
  #
  # metric_historyの先頭（直近の前期）から遡り、
  # 連続して値が減少（or boolean_falseの条件を満たす）している期数を返す。
  #
  # @param metric_history [Array<FinancialMetric>] fiscal_year_end降順
  # @param attr [Symbol] 判定対象の属性
  # @param direction [Symbol] :decreasing の場合は前の期>後の期を下落とみなす
  # @param boolean_false [Boolean] trueの場合、値がfalseの連続をカウント
  # @return [Integer]
  def self.get_consecutive_decline_count(metric_history, attr, direction: nil, boolean_false: false)
    count = 0

    if boolean_false
      metric_history.each do |m|
        val = m.public_send(attr)
        break unless val == false
        count += 1
      end
    elsif direction == :decreasing
      metric_history.each_cons(2) do |newer, older|
        newer_val = newer.public_send(attr)
        older_val = older.public_send(attr)
        break if newer_val.nil? || older_val.nil?
        break unless newer_val.to_f < older_val.to_f
        count += 1
      end
    else
      # YoYがマイナスの連続カウント
      metric_history.each do |m|
        val = m.public_send(attr)
        break if val.nil?
        break unless val.to_f < 0
        count += 1
      end
    end

    count
  end

  # 転換点属性Hashを構築するヘルパー
  #
  # @param pattern_type [Symbol]
  # @param significance [Symbol]
  # @param metric [FinancialMetric]
  # @param data [Hash] data_jsonに格納する追加データ
  # @return [Hash]
  def self.build_turning_point(pattern_type, significance, metric, **data)
    {
      company_id: metric.company_id,
      financial_metric_id: metric.id,
      fiscal_year_end: metric.fiscal_year_end,
      scope: metric.scope,
      period_type: metric.period_type,
      pattern_type: pattern_type,
      significance: significance,
      data_json: data.compact,
    }
  end
end
