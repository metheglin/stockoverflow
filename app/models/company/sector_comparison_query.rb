class Company::SectorComparisonQuery
  VALID_CONDITIONS = %i[above_average above_median top_quartile bottom_quartile].freeze

  attr_reader :metric, :condition, :classification, :scope_type, :period_type,
              :exclude_financial_sectors, :limit

  # @param metric [Symbol] 比較する指標（SectorMetric::METRIC_KEYS のいずれか）
  # @param condition [Symbol] 比較条件
  #   :above_average    - セクター平均を上回る企業
  #   :above_median     - セクター中央値を上回る企業
  #   :top_quartile     - セクター内Q3を上回る企業（上位25%）
  #   :bottom_quartile  - セクター内Q1を下回る企業（下位25%）
  # @param classification [Symbol] :sector_17 or :sector_33（デフォルト: :sector_33）
  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual（デフォルト: :annual）
  # @param exclude_financial_sectors [Boolean] 金融セクターを除外するか（デフォルト: false）
  # @param limit [Integer, nil] 取得件数上限
  def initialize(metric:, condition: :above_average, classification: :sector_33,
                 scope_type: :consolidated, period_type: :annual,
                 exclude_financial_sectors: false, limit: nil)
    @metric = metric
    @condition = condition
    @classification = classification
    @scope_type = scope_type
    @period_type = period_type
    @exclude_financial_sectors = exclude_financial_sectors
    @limit = limit
  end

  # クエリを実行し、条件を満たす企業のリストを返す
  #
  # @return [Array<Hash>]
  #
  # 返却例:
  #   [
  #     {
  #       company: #<Company>,
  #       metric: #<FinancialMetric>,
  #       value: 0.15,
  #       sector_code: "3050",
  #       sector_name: "情報・通信業",
  #       sector_stats: { "mean" => 0.08, "median" => 0.07, ... },
  #       relative_position: { vs_mean: 0.07, vs_median: 0.08, quartile: 4 },
  #     },
  #     ...
  #   ]
  #
  def execute
    sector_map = load_sector_map
    latest_metrics = load_latest_metrics
    threshold_map = build_threshold_map(sector_map)

    results = []

    latest_metrics.each do |fm|
      sector_code = get_sector_code(fm)
      next if sector_code.blank?
      next if @exclude_financial_sectors && SectorMetric.financial_sector?(sector_code)

      threshold = threshold_map[sector_code]
      next unless threshold

      value = SectorMetric.get_metric_value(fm, @metric)
      next if value.nil?
      next unless meets_condition?(value, threshold)

      sector_metric = sector_map[sector_code]
      sector_stats = sector_metric&.data_json&.dig(@metric.to_s)

      results << {
        company: fm.company,
        metric: fm,
        value: value.to_f,
        sector_code: sector_code,
        sector_name: sector_metric&.sector_name,
        sector_stats: sector_stats,
        relative_position: SectorMetric.get_relative_position(value.to_f, sector_stats),
      }
    end

    results = results.sort_by { |r| -(r[:value] || 0) }
    results = results.first(@limit) if @limit
    results
  end

  # セクターごとの閾値マップを構築する
  #
  # @param sector_map [Hash<String, SectorMetric>]
  # @return [Hash<String, Float>] { sector_code => threshold_value }
  def build_threshold_map(sector_map)
    stat_key = case @condition
               when :above_average then "mean"
               when :above_median then "median"
               when :top_quartile then "q3"
               when :bottom_quartile then "q1"
               else "mean"
               end

    sector_map.each_with_object({}) do |(code, sm), map|
      stats = sm.data_json&.dig(@metric.to_s)
      next unless stats

      map[code] = stats[stat_key]
    end
  end

  private

  def load_sector_map
    SectorMetric.load_latest_map(@classification)
  end

  def load_latest_metrics
    FinancialMetric
      .where(scope: @scope_type, period_type: @period_type)
      .where(
        "fiscal_year_end = (SELECT MAX(fm2.fiscal_year_end) FROM financial_metrics fm2 " \
        "WHERE fm2.company_id = financial_metrics.company_id " \
        "AND fm2.scope = financial_metrics.scope " \
        "AND fm2.period_type = financial_metrics.period_type)"
      )
      .includes(:company)
      .where(company_id: Company.listed.select(:id))
  end

  def get_sector_code(fm)
    if @classification == :sector_33
      fm.company.sector_33_code
    else
      fm.company.sector_17_code
    end
  end

  def meets_condition?(value, threshold)
    case @condition
    when :above_average, :above_median, :top_quartile
      value > threshold
    when :bottom_quartile
      value < threshold
    end
  end
end
