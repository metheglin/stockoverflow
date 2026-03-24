class DailyQuote < ApplicationRecord
  # JQUANTS V2 bars/daily → daily_quotes 固定カラム マッピング
  JQUANTS_FIELD_MAP = {
    "O"         => :open_price,
    "H"         => :high_price,
    "L"         => :low_price,
    "C"         => :close_price,
    "Vo"        => :volume,
    "Va"        => :turnover_value,
    "AdjFactor" => :adjustment_factor,
    "AdjC"      => :adjusted_close,
  }.freeze

  # JQUANTS V2 bars/daily → daily_quotes data_json マッピング
  JQUANTS_DATA_JSON_FIELDS = %w[AdjO AdjH AdjL AdjVo].freeze

  # 整数として扱うカラム
  INTEGER_COLUMNS = %i[volume turnover_value].freeze

  belongs_to :company

  # JQUANTS V2 bars/daily のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1件分のHash
  # @return [Hash] DailyQuote.create / update に渡せる属性Hash
  #
  # 例:
  #   attrs = DailyQuote.get_attributes_from_jquants(data)
  #   # => { open_price: 2047.0, high_price: 2069.0, ... }
  #
  def self.get_attributes_from_jquants(data)
    attrs = {}
    JQUANTS_FIELD_MAP.each do |jquants_key, column|
      raw_value = data[jquants_key]
      next if raw_value.nil?

      attrs[column] = INTEGER_COLUMNS.include?(column) ? raw_value.to_i : raw_value
    end

    # data_json に格納するフィールド
    json_data = {}
    JQUANTS_DATA_JSON_FIELDS.each do |key|
      json_data[key.underscore] = data[key] if data[key].present?
    end
    attrs[:data_json] = json_data if json_data.any?

    attrs
  end

  # 移動平均を算出する
  #
  # quotesはtraded_on昇順にソートされたDailyQuoteの配列を前提とする。
  # 各ウィンドウ幅について、配列末尾からwindow件分の adjusted_close（なければ close_price）の
  # 単純移動平均を算出する。データが不足するウィンドウはスキップされる。
  #
  # @param quotes [Array<DailyQuote>] traded_on昇順ソート済みの株価配列
  # @param windows [Array<Integer>] 移動平均のウィンドウ幅
  # @return [Hash<Integer, Float>] { window => moving_average_value }
  #
  # 例:
  #   mas = DailyQuote.get_moving_averages(quotes, windows: [5, 25])
  #   # => { 5 => 1520.0, 25 => 1480.5 }
  #
  def self.get_moving_averages(quotes, windows: [5, 25, 75, 200])
    return {} if quotes.empty?

    result = {}
    windows.each do |window|
      recent = quotes.last(window)
      next if recent.size < window

      prices = recent.map { |q| q.adjusted_close || q.close_price }
      next if prices.any?(&:nil?)

      result[window] = (prices.sum.to_d / window).round(2).to_f
    end
    result
  end

  # 出来高移動平均を算出する
  #
  # @param quotes [Array<DailyQuote>] traded_on昇順ソート済みの株価配列
  # @param window [Integer] ウィンドウ幅
  # @return [Integer, nil] 出来高移動平均（整数）。データ不足の場合はnil
  #
  # 例:
  #   avg = DailyQuote.get_volume_average(quotes, window: 25)
  #   # => 150000
  #
  def self.get_volume_average(quotes, window: 25)
    return nil if quotes.empty?

    recent = quotes.last(window)
    return nil if recent.size < window

    volumes = recent.map(&:volume)
    return nil if volumes.any?(&:nil?)

    (volumes.sum.to_d / window).round(0).to_i
  end

  # 株価と移動平均の乖離率を算出する
  #
  # 現在株価が短期MA・長期MAのそれぞれ何%上（または下）にあるかを返す。
  # 正の値は株価がMAより上、負の値は下を意味する。
  #
  # @param price [Numeric, nil] 現在株価
  # @param ma_short [Numeric, nil] 短期移動平均
  # @param ma_long [Numeric, nil] 長期移動平均
  # @return [Hash] { short_deviation: Float, long_deviation: Float }
  #
  # 例:
  #   DailyQuote.get_price_position(1050, 1000, 950)
  #   # => { short_deviation: 0.05, long_deviation: 0.1053 }
  #
  def self.get_price_position(price, ma_short, ma_long)
    result = {}

    if price && ma_short && ma_short > 0
      result[:short_deviation] = ((price.to_d - ma_short.to_d) / ma_short.to_d).round(4).to_f
    end

    if price && ma_long && ma_long > 0
      result[:long_deviation] = ((price.to_d - ma_long.to_d) / ma_long.to_d).round(4).to_f
    end

    result
  end

  # ゴールデンクロス/デッドクロスを検出する
  #
  # 直近日において短期MAが長期MAを下から上に突き抜けた場合は :golden_cross、
  # 上から下に突き抜けた場合は :dead_cross を返す。クロスが発生していない場合はnil。
  #
  # @param quotes [Array<DailyQuote>] traded_on昇順ソート済みの株価配列
  # @param short_window [Integer] 短期MA期間（デフォルト: 25）
  # @param long_window [Integer] 長期MA期間（デフォルト: 75）
  # @return [Symbol, nil] :golden_cross, :dead_cross, or nil
  #
  def self.detect_cross(quotes, short_window: 25, long_window: 75)
    return nil if quotes.size < long_window + 1

    current_mas = get_moving_averages(quotes, windows: [short_window, long_window])
    return nil unless current_mas[short_window] && current_mas[long_window]

    prev_quotes = quotes[0..-2]
    prev_mas = get_moving_averages(prev_quotes, windows: [short_window, long_window])
    return nil unless prev_mas[short_window] && prev_mas[long_window]

    current_short_above = current_mas[short_window] >= current_mas[long_window]
    prev_short_above = prev_mas[short_window] >= prev_mas[long_window]

    if current_short_above && !prev_short_above
      :golden_cross
    elsif !current_short_above && prev_short_above
      :dead_cross
    end
  end

  # 出来高急増を検出する
  #
  # 直近lookback日間において、出来高がwindow日平均のthreshold倍を超えた日を検出する。
  # 各日の出来高平均はその日より前のwindow日間で算出する。
  #
  # @param quotes [Array<DailyQuote>] traded_on昇順ソート済みの株価配列
  # @param window [Integer] 出来高平均のウィンドウ幅（デフォルト: 25）
  # @param threshold [Numeric] 倍率閾値（デフォルト: 2.0）
  # @param lookback [Integer] 直近何日間をチェックするか（デフォルト: 5）
  # @return [Array<Hash>] 急増した日のリスト
  #
  # 例:
  #   spikes = DailyQuote.detect_volume_spikes(quotes)
  #   # => [{ traded_on: Date, volume: 500000, average: 150000, ratio: 3.33 }]
  #
  def self.detect_volume_spikes(quotes, window: 25, threshold: 2.0, lookback: 5)
    return [] if quotes.size <= window

    spikes = []
    check_count = [lookback, quotes.size - window].min

    check_count.times do |i|
      target_idx = quotes.size - 1 - i
      target = quotes[target_idx]
      next if target.volume.nil?

      avg_start = target_idx - window
      next if avg_start < 0

      preceding = quotes[avg_start...target_idx]
      next if preceding.size < window

      volumes = preceding.map(&:volume)
      next if volumes.any?(&:nil?)

      avg = volumes.sum.to_d / window
      next if avg == 0

      ratio = (target.volume.to_d / avg).round(2).to_f

      if ratio >= threshold
        spikes << {
          traded_on: target.traded_on,
          volume: target.volume,
          average: avg.round(0).to_i,
          ratio: ratio,
        }
      end
    end

    spikes
  end
end
