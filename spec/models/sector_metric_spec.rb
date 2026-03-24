require "rails_helper"

RSpec.describe SectorMetric do
  describe ".get_statistics" do
    it "正常な値の配列から統計量が正しく算出される" do
      values = [0.05, 0.08, 0.12, 0.03, 0.15]
      result = SectorMetric.get_statistics(values)

      expect(result["count"]).to eq(5)
      expect(result["mean"]).to be_within(0.0001).of(0.086)
      expect(result["median"]).to be_within(0.0001).of(0.08)
      expect(result["min"]).to eq(0.03)
      expect(result["max"]).to eq(0.15)
      expect(result["q1"]).to be_a(Float)
      expect(result["q3"]).to be_a(Float)
      expect(result["stddev"]).to be_a(Float)
    end

    it "nilを含む配列からnilが除外されて算出される" do
      values = [0.05, nil, 0.10, nil, 0.15]
      result = SectorMetric.get_statistics(values)

      expect(result["count"]).to eq(3)
      expect(result["mean"]).to eq(0.1)
    end

    it "空の配列でnilが返る" do
      expect(SectorMetric.get_statistics([])).to be_nil
    end

    it "全てnilの配列でnilが返る" do
      expect(SectorMetric.get_statistics([nil, nil, nil])).to be_nil
    end

    it "1要素の配列で mean = median = q1 = q3 = min = max である" do
      result = SectorMetric.get_statistics([0.08])

      expect(result["count"]).to eq(1)
      expect(result["mean"]).to eq(0.08)
      expect(result["median"]).to eq(0.08)
      expect(result["q1"]).to eq(0.08)
      expect(result["q3"]).to eq(0.08)
      expect(result["min"]).to eq(0.08)
      expect(result["max"]).to eq(0.08)
      expect(result["stddev"]).to eq(0.0)
    end

    it "全要素が同じ値の場合 stddev が 0.0 である" do
      result = SectorMetric.get_statistics([0.10, 0.10, 0.10, 0.10])

      expect(result["stddev"]).to eq(0.0)
      expect(result["mean"]).to eq(0.1)
      expect(result["median"]).to eq(0.1)
    end
  end

  describe ".get_percentile_value" do
    it "ソート済み配列の中央値（50パーセンタイル）が正しい" do
      sorted = [1.0, 2.0, 3.0, 4.0, 5.0]
      expect(SectorMetric.get_percentile_value(sorted, 50)).to eq(3.0)
    end

    it "偶数個の配列の中央値が線形補間される" do
      sorted = [1.0, 2.0, 3.0, 4.0]
      expect(SectorMetric.get_percentile_value(sorted, 50)).to eq(2.5)
    end

    it "25パーセンタイル（Q1）が正しい" do
      sorted = [1.0, 2.0, 3.0, 4.0, 5.0]
      expect(SectorMetric.get_percentile_value(sorted, 25)).to eq(2.0)
    end

    it "75パーセンタイル（Q3）が正しい" do
      sorted = [1.0, 2.0, 3.0, 4.0, 5.0]
      expect(SectorMetric.get_percentile_value(sorted, 75)).to eq(4.0)
    end

    it "1要素の配列でその値が返る" do
      expect(SectorMetric.get_percentile_value([5.0], 50)).to eq(5.0)
    end
  end

  describe ".get_stddev" do
    it "正常な値の標準偏差が正しい" do
      values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
      mean = values.sum / values.length
      stddev = SectorMetric.get_stddev(values, mean)

      expect(stddev).to be_within(0.001).of(2.0)
    end

    it "1要素の配列で 0.0 が返る" do
      expect(SectorMetric.get_stddev([5.0], 5.0)).to eq(0.0)
    end
  end

  describe ".get_metric_value" do
    it "固定カラム指標（roe等）が正しく読み取れる" do
      metric = FinancialMetric.new(roe: BigDecimal("0.08"))
      expect(SectorMetric.get_metric_value(metric, :roe)).to eq(BigDecimal("0.08"))
    end

    it "data_json指標（per等）が正しく読み取れる" do
      metric = FinancialMetric.new
      allow(metric).to receive(:per).and_return(15.5)
      expect(SectorMetric.get_metric_value(metric, :per)).to eq(15.5)
    end

    it "存在しないメソッドでnilが返る" do
      metric = FinancialMetric.new
      expect(SectorMetric.get_metric_value(metric, :nonexistent_method)).to be_nil
    end
  end

  describe ".get_relative_position" do
    let(:stats) do
      {
        "mean" => 0.08,
        "median" => 0.07,
        "q1" => 0.04,
        "q3" => 0.12,
        "min" => -0.05,
        "max" => 0.25,
      }
    end

    it "セクター平均を上回る値の relative_position が正しい" do
      result = SectorMetric.get_relative_position(0.15, stats)

      expect(result[:vs_mean]).to eq(0.07)
      expect(result[:vs_median]).to eq(0.08)
      expect(result[:quartile]).to eq(4)
    end

    it "Q1以下の値で quartile: 1 が返る" do
      result = SectorMetric.get_relative_position(0.02, stats)
      expect(result[:quartile]).to eq(1)
    end

    it "Q1超かつmedian以下で quartile: 2 が返る" do
      result = SectorMetric.get_relative_position(0.06, stats)
      expect(result[:quartile]).to eq(2)
    end

    it "Q3超の値で quartile: 4 が返る" do
      result = SectorMetric.get_relative_position(0.20, stats)
      expect(result[:quartile]).to eq(4)
    end

    it "value が nil の場合 nil が返る" do
      expect(SectorMetric.get_relative_position(nil, stats)).to be_nil
    end

    it "sector_stats が nil の場合 nil が返る" do
      expect(SectorMetric.get_relative_position(0.10, nil)).to be_nil
    end
  end

  describe ".financial_sector?" do
    it "金融セクターコードでtrueを返す" do
      expect(SectorMetric.financial_sector?("7050")).to be true
      expect(SectorMetric.financial_sector?("7100")).to be true
      expect(SectorMetric.financial_sector?("7150")).to be true
      expect(SectorMetric.financial_sector?("7200")).to be true
    end

    it "非金融セクターコードでfalseを返す" do
      expect(SectorMetric.financial_sector?("3050")).to be false
      expect(SectorMetric.financial_sector?("5250")).to be false
    end
  end
end
