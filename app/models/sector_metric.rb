class SectorMetric < ApplicationRecord
  # 集計対象の指標キー
  #
  # 固定カラム指標: FinancialMetric の固定カラムから読み取り
  # data_json指標: FinancialMetric の data_json から読み取り
  FIXED_COLUMN_METRICS = %i[
    roe roa operating_margin net_margin
    revenue_yoy net_income_yoy
  ].freeze

  DATA_JSON_METRICS = %i[
    per pbr psr ev_ebitda dividend_yield
    current_ratio debt_to_equity net_debt_to_equity
    asset_turnover gross_margin sga_ratio
  ].freeze

  METRIC_KEYS = (FIXED_COLUMN_METRICS + DATA_JSON_METRICS).freeze

  # 金融セクター（33業種分類）
  # 銀行業・証券商品先物取引業・保険業・その他金融業は
  # ROE/ROA等の比較において一般事業会社と財務構造が大きく異なる
  FINANCIAL_SECTOR_33_CODES = %w[7050 7100 7150 7200].freeze

  enum :classification, {
    sector_17: 0,
    sector_33: 1,
  }

  # 配列から統計量を算出する
  #
  # @param values [Array<Numeric>] 指標値の配列（nil含む可能性あり）
  # @return [Hash, nil] 統計量Hash。有効値が0件の場合nil
  #
  # 例:
  #   SectorMetric.get_statistics([0.05, 0.08, 0.12, 0.03, 0.15])
  #   # => { "mean" => 0.086, "median" => 0.08, "q1" => 0.05, "q3" => 0.12,
  #   #      "min" => 0.03, "max" => 0.15, "stddev" => 0.0441, "count" => 5 }
  #
  def self.get_statistics(values)
    compacted = values.compact.map(&:to_f)
    return nil if compacted.empty?

    sorted = compacted.sort
    count = sorted.length
    mean = sorted.sum / count

    {
      "mean" => mean.round(4),
      "median" => get_percentile_value(sorted, 50),
      "q1" => get_percentile_value(sorted, 25),
      "q3" => get_percentile_value(sorted, 75),
      "min" => sorted.first.round(4),
      "max" => sorted.last.round(4),
      "stddev" => get_stddev(sorted, mean),
      "count" => count,
    }
  end

  # ソート済み配列からパーセンタイル値を算出する（線形補間法）
  #
  # @param sorted [Array<Float>] 昇順ソート済み配列
  # @param percentile [Numeric] パーセンタイル（0〜100）
  # @return [Float]
  def self.get_percentile_value(sorted, percentile)
    return sorted.first.round(4) if sorted.length == 1

    rank = (percentile / 100.0) * (sorted.length - 1)
    lower = sorted[rank.floor]
    upper = sorted[rank.ceil]

    (lower + (upper - lower) * (rank - rank.floor)).round(4)
  end

  # 標準偏差を算出する
  #
  # @param sorted [Array<Float>] 値の配列
  # @param mean [Float] 平均値
  # @return [Float]
  def self.get_stddev(sorted, mean)
    return 0.0 if sorted.length <= 1

    variance = sorted.sum { |v| (v - mean) ** 2 } / sorted.length
    Math.sqrt(variance).round(4)
  end

  # FinancialMetric から指標値を読み取る
  #
  # 固定カラム指標は直接アクセス、data_json指標はJsonAttributeゲッター経由で取得
  #
  # @param metric [FinancialMetric]
  # @param metric_key [Symbol] METRIC_KEYS のいずれか
  # @return [Numeric, nil]
  def self.get_metric_value(metric, metric_key)
    metric.public_send(metric_key)
  rescue NoMethodError
    nil
  end

  # 特定指標について、セクターの統計量に対する値の相対位置を判定する
  #
  # @param value [Numeric, nil] 個別企業の指標値
  # @param sector_stats [Hash] get_statistics の返却値
  # @return [Hash, nil] { vs_mean:, vs_median:, quartile: }
  #
  # 例:
  #   stats = { "mean" => 0.08, "median" => 0.07, "q1" => 0.04, "q3" => 0.12, ... }
  #   SectorMetric.get_relative_position(0.15, stats)
  #   # => { vs_mean: 0.07, vs_median: 0.08, quartile: 4 }
  #
  def self.get_relative_position(value, sector_stats)
    return nil if value.nil? || sector_stats.nil?

    q1 = sector_stats["q1"]
    median = sector_stats["median"]
    q3 = sector_stats["q3"]
    mean = sector_stats["mean"]

    quartile = if value <= q1
                 1
               elsif value <= median
                 2
               elsif value <= q3
                 3
               else
                 4
               end

    {
      vs_mean: (value - mean).round(4),
      vs_median: (value - median).round(4),
      quartile: quartile,
    }
  end

  # 金融セクターかどうかを判定する
  #
  # @param sector_33_code [String]
  # @return [Boolean]
  def self.financial_sector?(sector_33_code)
    FINANCIAL_SECTOR_33_CODES.include?(sector_33_code.to_s)
  end

  # 最新のスナップショット日を取得する
  #
  # @param classification [Symbol] :sector_17 or :sector_33
  # @return [Date, nil]
  def self.load_latest_calculated_on(classification)
    where(classification: classification).maximum(:calculated_on)
  end

  # 最新スナップショットのセクター統計をsector_codeをキーとしたHashで返す
  #
  # @param classification [Symbol] :sector_17 or :sector_33
  # @param calculated_on [Date, nil] nil の場合は最新日
  # @return [Hash<String, SectorMetric>] { sector_code => SectorMetric }
  def self.load_latest_map(classification, calculated_on: nil)
    date = calculated_on || load_latest_calculated_on(classification)
    return {} unless date

    where(classification: classification, calculated_on: date)
      .index_by(&:sector_code)
  end
end
