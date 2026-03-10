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
end
