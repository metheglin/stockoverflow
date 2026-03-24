class DailyQuote::TechnicalScreeningQuery
  SCREEN_TYPES = %i[golden_cross dead_cross volume_spike].freeze

  # 非営業日を考慮した暦日換算係数（営業日数 × 係数 = 必要な暦日数の概算）
  CALENDAR_DAY_RATIO = 1.6

  attr_reader :screen_type, :reference_date, :short_window, :long_window,
              :volume_window, :volume_threshold, :volume_lookback, :limit

  # @param screen_type [Symbol] スクリーニング種別（:golden_cross, :dead_cross, :volume_spike）
  # @param reference_date [Date] 基準日（デフォルト: 当日）
  # @param short_window [Integer] 短期MA期間（デフォルト: 25）
  # @param long_window [Integer] 長期MA期間（デフォルト: 75）
  # @param volume_window [Integer] 出来高平均のウィンドウ幅（デフォルト: 25）
  # @param volume_threshold [Numeric] 出来高急増の倍率閾値（デフォルト: 2.0）
  # @param volume_lookback [Integer] 出来高急増チェックの遡り日数（デフォルト: 5）
  # @param limit [Integer, nil] 取得件数上限
  def initialize(screen_type:, reference_date: Date.current,
                 short_window: 25, long_window: 75,
                 volume_window: 25, volume_threshold: 2.0, volume_lookback: 5,
                 limit: nil)
    @screen_type = screen_type
    @reference_date = reference_date
    @short_window = short_window
    @long_window = long_window
    @volume_window = volume_window
    @volume_threshold = volume_threshold
    @volume_lookback = volume_lookback
    @limit = limit
  end

  # スクリーニングを実行し、条件を満たす企業のリストを返す
  #
  # @return [Array<Hash>]
  #
  # 返却例（golden_cross / dead_cross）:
  #   [
  #     {
  #       company: #<Company>,
  #       traded_on: Date,
  #       close_price: 1520.0,
  #       moving_averages: { 25 => 1500.0, 75 => 1480.0 },
  #       position: { short_deviation: 0.0133, long_deviation: 0.027 },
  #     },
  #   ]
  #
  # 返却例（volume_spike）:
  #   [
  #     {
  #       company: #<Company>,
  #       traded_on: Date,
  #       close_price: 1520.0,
  #       spikes: [{ traded_on: Date, volume: 500000, average: 150000, ratio: 3.33 }],
  #       max_ratio: 3.33,
  #     },
  #   ]
  #
  def execute
    quotes_by_company = load_quotes
    results = []

    quotes_by_company.each do |_company_id, quotes|
      result = screen_company(quotes)
      results << result if result
    end

    results = sort_results(results)
    results = results.first(@limit) if @limit
    results
  end

  private

  def load_quotes
    required_trading_days = get_required_trading_days
    calendar_days = (required_trading_days * CALENDAR_DAY_RATIO).ceil
    start_date = @reference_date - calendar_days

    DailyQuote
      .joins(:company)
      .merge(Company.listed)
      .where(traded_on: start_date..@reference_date)
      .order(:company_id, :traded_on)
      .includes(:company)
      .group_by(&:company_id)
  end

  def get_required_trading_days
    case @screen_type
    when :golden_cross, :dead_cross
      @long_window + 1
    when :volume_spike
      @volume_window + @volume_lookback
    else
      200
    end
  end

  def screen_company(quotes)
    case @screen_type
    when :golden_cross, :dead_cross
      screen_cross(quotes)
    when :volume_spike
      screen_volume_spike(quotes)
    end
  end

  def screen_cross(quotes)
    cross = DailyQuote.detect_cross(quotes, short_window: @short_window, long_window: @long_window)
    return nil unless cross == @screen_type

    mas = DailyQuote.get_moving_averages(quotes, windows: [@short_window, @long_window])
    latest = quotes.last
    price = (latest.adjusted_close || latest.close_price)&.to_f
    position = DailyQuote.get_price_position(price, mas[@short_window], mas[@long_window])

    {
      company: latest.company,
      traded_on: latest.traded_on,
      close_price: price,
      moving_averages: mas,
      position: position,
    }
  end

  def screen_volume_spike(quotes)
    spikes = DailyQuote.detect_volume_spikes(
      quotes, window: @volume_window, threshold: @volume_threshold, lookback: @volume_lookback
    )
    return nil if spikes.empty?

    latest = quotes.last
    price = (latest.adjusted_close || latest.close_price)&.to_f
    max_spike = spikes.max_by { |s| s[:ratio] }

    {
      company: latest.company,
      traded_on: latest.traded_on,
      close_price: price,
      spikes: spikes,
      max_ratio: max_spike[:ratio],
    }
  end

  def sort_results(results)
    case @screen_type
    when :golden_cross, :dead_cross
      results.sort_by { |r| -(r.dig(:position, :short_deviation) || 0) }
    when :volume_spike
      results.sort_by { |r| -(r[:max_ratio] || 0) }
    else
      results
    end
  end
end
