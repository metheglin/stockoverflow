require "rails_helper"

RSpec.describe DailyQuote do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Date" => "2024-01-15",
        "Code" => "86970",
        "O" => 2047.0,
        "H" => 2069.0,
        "L" => 2035.0,
        "C" => 2045.0,
        "Vo" => 2202500.0,
        "Va" => 4507051850.0,
        "AdjFactor" => 1.0,
        "AdjO" => 2047.0,
        "AdjH" => 2069.0,
        "AdjL" => 2035.0,
        "AdjC" => 2045.0,
        "AdjVo" => 2202500.0,
      }
    end

    it "固定カラムの属性が正しく変換される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:open_price]).to eq(2047.0)
      expect(attrs[:high_price]).to eq(2069.0)
      expect(attrs[:low_price]).to eq(2035.0)
      expect(attrs[:close_price]).to eq(2045.0)
      expect(attrs[:volume]).to eq(2202500)
      expect(attrs[:turnover_value]).to eq(4507051850)
      expect(attrs[:adjustment_factor]).to eq(1.0)
      expect(attrs[:adjusted_close]).to eq(2045.0)
    end

    it "data_jsonフィールドが正しく設定される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:data_json]).to include(
        "adj_o" => 2047.0,
        "adj_h" => 2069.0,
        "adj_l" => 2035.0,
        "adj_vo" => 2202500.0,
      )
    end

    it "volume, turnover_valueは整数に変換される" do
      attrs = DailyQuote.get_attributes_from_jquants(jquants_data)

      expect(attrs[:volume]).to be_a(Integer)
      expect(attrs[:turnover_value]).to be_a(Integer)
    end

    it "nilの値はスキップされる" do
      data = { "O" => nil, "C" => 2045.0 }
      attrs = DailyQuote.get_attributes_from_jquants(data)

      expect(attrs).not_to have_key(:open_price)
      expect(attrs[:close_price]).to eq(2045.0)
    end
  end

  # テスト用ヘルパー: DailyQuoteインスタンスを生成する
  def build_quote(adjusted_close:, volume: 100_000, close_price: nil, traded_on: nil)
    DailyQuote.new(
      adjusted_close: adjusted_close,
      close_price: close_price || adjusted_close,
      volume: volume,
      traded_on: traded_on,
    )
  end

  def build_quotes_from_prices(prices, base_volume: 100_000)
    prices.each_with_index.map do |price, i|
      build_quote(
        adjusted_close: price,
        volume: base_volume,
        traded_on: Date.new(2025, 1, 6) + i,
      )
    end
  end

  describe ".get_moving_averages" do
    it "各ウィンドウ幅の移動平均を正しく算出する" do
      prices = (1..10).map { |i| i * 100.0 }
      quotes = build_quotes_from_prices(prices)

      result = DailyQuote.get_moving_averages(quotes, windows: [3, 5, 10])

      # 末尾3件: 800, 900, 1000 → 平均 900.0
      expect(result[3]).to eq(900.0)
      # 末尾5件: 600, 700, 800, 900, 1000 → 平均 800.0
      expect(result[5]).to eq(800.0)
      # 全10件: 100..1000 → 平均 550.0
      expect(result[10]).to eq(550.0)
    end

    it "データが不足するウィンドウはスキップされる" do
      prices = [100.0, 200.0, 300.0]
      quotes = build_quotes_from_prices(prices)

      result = DailyQuote.get_moving_averages(quotes, windows: [3, 5])

      expect(result[3]).to eq(200.0)
      expect(result).not_to have_key(5)
    end

    it "空配列の場合は空Hashを返す" do
      result = DailyQuote.get_moving_averages([], windows: [5])

      expect(result).to eq({})
    end

    it "adjusted_closeがnilの場合はclose_priceを使用する" do
      quotes = [
        build_quote(adjusted_close: nil, close_price: 100.0),
        build_quote(adjusted_close: nil, close_price: 200.0),
        build_quote(adjusted_close: nil, close_price: 300.0),
      ]

      result = DailyQuote.get_moving_averages(quotes, windows: [3])

      expect(result[3]).to eq(200.0)
    end

    it "close_priceもnilの場合はそのウィンドウをスキップする" do
      quotes = [
        build_quote(adjusted_close: 100.0),
        build_quote(adjusted_close: nil, close_price: nil),
        build_quote(adjusted_close: 300.0),
      ]

      result = DailyQuote.get_moving_averages(quotes, windows: [3])

      expect(result).not_to have_key(3)
    end
  end

  describe ".get_volume_average" do
    it "出来高移動平均を正しく算出する" do
      quotes = (1..5).map do |i|
        build_quote(adjusted_close: 1000.0, volume: i * 10_000)
      end

      result = DailyQuote.get_volume_average(quotes, window: 5)

      # (10000 + 20000 + 30000 + 40000 + 50000) / 5 = 30000
      expect(result).to eq(30_000)
    end

    it "データ不足の場合はnilを返す" do
      quotes = [build_quote(adjusted_close: 1000.0, volume: 50_000)]

      result = DailyQuote.get_volume_average(quotes, window: 5)

      expect(result).to be_nil
    end

    it "空配列の場合はnilを返す" do
      expect(DailyQuote.get_volume_average([], window: 5)).to be_nil
    end

    it "volumeにnilが含まれる場合はnilを返す" do
      quotes = [
        build_quote(adjusted_close: 1000.0, volume: 10_000),
        build_quote(adjusted_close: 1000.0, volume: nil),
        build_quote(adjusted_close: 1000.0, volume: 30_000),
      ]

      result = DailyQuote.get_volume_average(quotes, window: 3)

      expect(result).to be_nil
    end

    it "整数を返す" do
      quotes = (1..3).map { build_quote(adjusted_close: 1000.0, volume: 10_001) }

      result = DailyQuote.get_volume_average(quotes, window: 3)

      expect(result).to be_a(Integer)
      expect(result).to eq(10_001)
    end
  end

  describe ".get_price_position" do
    it "株価がMAより上にある場合は正の乖離率を返す" do
      result = DailyQuote.get_price_position(1050.0, 1000.0, 950.0)

      expect(result[:short_deviation]).to eq(0.05)
      expect(result[:long_deviation]).to be_within(0.0001).of(0.1053)
    end

    it "株価がMAより下にある場合は負の乖離率を返す" do
      result = DailyQuote.get_price_position(950.0, 1000.0, 1050.0)

      expect(result[:short_deviation]).to eq(-0.05)
      expect(result[:long_deviation]).to be_within(0.0001).of(-0.0952)
    end

    it "株価がMAと同じ場合は0を返す" do
      result = DailyQuote.get_price_position(1000.0, 1000.0, 1000.0)

      expect(result[:short_deviation]).to eq(0.0)
      expect(result[:long_deviation]).to eq(0.0)
    end

    it "ma_shortがnilの場合はshort_deviationをスキップする" do
      result = DailyQuote.get_price_position(1000.0, nil, 950.0)

      expect(result).not_to have_key(:short_deviation)
      expect(result).to have_key(:long_deviation)
    end

    it "ma_longがnilの場合はlong_deviationをスキップする" do
      result = DailyQuote.get_price_position(1000.0, 950.0, nil)

      expect(result).to have_key(:short_deviation)
      expect(result).not_to have_key(:long_deviation)
    end

    it "priceがnilの場合は空Hashを返す" do
      result = DailyQuote.get_price_position(nil, 1000.0, 950.0)

      expect(result).to eq({})
    end

    it "ma_shortが0の場合はshort_deviationをスキップする" do
      result = DailyQuote.get_price_position(1000.0, 0, 950.0)

      expect(result).not_to have_key(:short_deviation)
      expect(result).to have_key(:long_deviation)
    end
  end

  describe ".detect_cross" do
    # ゴールデンクロスのテストデータを構築する
    # 短期MA(window=3)が長期MA(window=5)を下から上に突き抜けるシナリオ
    #
    # 前日まで(6データ): 株価が下降→横ばいで、3日MAが5日MAより下
    # 最終日: 株価が大きく上昇し、3日MAが5日MAより上に
    def build_golden_cross_quotes
      # 6日分のデータ（short=3, long=5なので最低6日=long+1必要）
      # Day1: 1000, Day2: 980, Day3: 960, Day4: 950, Day5: 940, Day6: 1020
      #
      # Day5まで: 3日MA = (960+950+940)/3 = 950.0, 5日MA = (1000+980+960+950+940)/5 = 966.0
      #   → 短期 < 長期（950 < 966）
      # Day6時点: 3日MA = (950+940+1020)/3 = 970.0, 5日MA = (980+960+950+940+1020)/5 = 970.0
      #   → 短期 >= 長期（970 >= 970）
      build_quotes_from_prices([1000.0, 980.0, 960.0, 950.0, 940.0, 1020.0])
    end

    it "ゴールデンクロスを検出する" do
      quotes = build_golden_cross_quotes

      result = DailyQuote.detect_cross(quotes, short_window: 3, long_window: 5)

      expect(result).to eq(:golden_cross)
    end

    it "デッドクロスを検出する" do
      # 株価が上昇→急落で、短期MAが長期MAを上から下に突き抜ける
      # Day1: 940, Day2: 950, Day3: 960, Day4: 980, Day5: 1000, Day6: 900
      #
      # Day5まで: 3日MA = (960+980+1000)/3 = 980.0, 5日MA = (940+950+960+980+1000)/5 = 966.0
      #   → 短期 > 長期（980 > 966）
      # Day6時点: 3日MA = (980+1000+900)/3 = 960.0, 5日MA = (950+960+980+1000+900)/5 = 958.0
      #   → 短期 > 長期（960 > 958）... これだとクロスしない
      #
      # 修正: Day6をもっと低くする
      # Day1: 940, Day2: 950, Day3: 960, Day4: 980, Day5: 1000, Day6: 850
      # Day5まで: 3日MA = 980.0, 5日MA = 966.0 → 短期 > 長期
      # Day6時点: 3日MA = (980+1000+850)/3 = 943.33, 5日MA = (950+960+980+1000+850)/5 = 948.0
      #   → 短期 < 長期（943.33 < 948）
      quotes = build_quotes_from_prices([940.0, 950.0, 960.0, 980.0, 1000.0, 850.0])

      result = DailyQuote.detect_cross(quotes, short_window: 3, long_window: 5)

      expect(result).to eq(:dead_cross)
    end

    it "クロスが発生していない場合はnilを返す" do
      # 一貫して上昇: 短期MAは常に長期MAより上
      quotes = build_quotes_from_prices([100.0, 200.0, 300.0, 400.0, 500.0, 600.0])

      result = DailyQuote.detect_cross(quotes, short_window: 3, long_window: 5)

      expect(result).to be_nil
    end

    it "データ不足の場合はnilを返す" do
      quotes = build_quotes_from_prices([100.0, 200.0, 300.0])

      result = DailyQuote.detect_cross(quotes, short_window: 3, long_window: 5)

      expect(result).to be_nil
    end
  end

  describe ".detect_volume_spikes" do
    it "出来高急増を検出する" do
      # 25日分の通常出来高 + 急増日
      normal_quotes = (1..25).map do |i|
        build_quote(
          adjusted_close: 1000.0,
          volume: 100_000,
          traded_on: Date.new(2025, 1, 6) + i,
        )
      end
      spike_quote = build_quote(
        adjusted_close: 1050.0,
        volume: 300_000,
        traded_on: Date.new(2025, 2, 1),
      )
      quotes = normal_quotes + [spike_quote]

      result = DailyQuote.detect_volume_spikes(quotes, window: 25, threshold: 2.0, lookback: 1)

      expect(result.size).to eq(1)
      expect(result[0][:volume]).to eq(300_000)
      expect(result[0][:average]).to eq(100_000)
      expect(result[0][:ratio]).to eq(3.0)
    end

    it "閾値未満の場合は空配列を返す" do
      quotes = (1..26).map do |i|
        build_quote(
          adjusted_close: 1000.0,
          volume: 100_000,
          traded_on: Date.new(2025, 1, 6) + i,
        )
      end

      result = DailyQuote.detect_volume_spikes(quotes, window: 25, threshold: 2.0, lookback: 1)

      expect(result).to eq([])
    end

    it "lookback期間内の複数のスパイクを検出する" do
      normal_quotes = (1..25).map do |i|
        build_quote(
          adjusted_close: 1000.0,
          volume: 100_000,
          traded_on: Date.new(2025, 1, 6) + i,
        )
      end
      spike1 = build_quote(adjusted_close: 1050.0, volume: 250_000, traded_on: Date.new(2025, 2, 1))
      spike2 = build_quote(adjusted_close: 1060.0, volume: 350_000, traded_on: Date.new(2025, 2, 2))
      quotes = normal_quotes + [spike1, spike2]

      result = DailyQuote.detect_volume_spikes(quotes, window: 25, threshold: 2.0, lookback: 2)

      expect(result.size).to eq(2)
    end

    it "データ不足の場合は空配列を返す" do
      quotes = (1..10).map do |i|
        build_quote(adjusted_close: 1000.0, volume: 100_000, traded_on: Date.new(2025, 1, 6) + i)
      end

      result = DailyQuote.detect_volume_spikes(quotes, window: 25, threshold: 2.0)

      expect(result).to eq([])
    end

    it "空配列の場合は空配列を返す" do
      expect(DailyQuote.detect_volume_spikes([])).to eq([])
    end

    it "出来高がnilの日はスキップされる" do
      normal_quotes = (1..25).map do |i|
        build_quote(adjusted_close: 1000.0, volume: 100_000, traded_on: Date.new(2025, 1, 6) + i)
      end
      nil_volume_quote = build_quote(adjusted_close: 1050.0, volume: nil, traded_on: Date.new(2025, 2, 1))
      quotes = normal_quotes + [nil_volume_quote]

      result = DailyQuote.detect_volume_spikes(quotes, window: 25, threshold: 2.0, lookback: 1)

      expect(result).to eq([])
    end
  end
end
