require "rails_helper"

RSpec.describe Company::DashboardSummary do
  let(:company) { Company.new(id: 1, securities_code: "7203", name: "トヨタ自動車", sector_33_code: "3700") }

  let(:timeline_data) do
    [
      {
        fiscal_year_end: Date.new(2023, 3, 31),
        financial_value: nil,
        financial_metric: nil,
        values: {
          net_sales: 30_000_000, operating_income: 3_000_000, net_income: 2_000_000,
          eps: 150.0, bps: 2000.0,
          operating_cf: 5_000_000, investing_cf: -2_000_000, financing_cf: -1_000_000,
        },
        metrics: {
          revenue_yoy: 0.10, operating_income_yoy: 0.15, net_income_yoy: 0.12,
          roe: 0.08, roa: 0.05, operating_margin: 0.10, net_margin: 0.067,
          free_cf: 3_000_000, per: 12.5, pbr: 1.2,
        },
      },
      {
        fiscal_year_end: Date.new(2024, 3, 31),
        financial_value: nil,
        financial_metric: nil,
        values: {
          net_sales: 35_000_000, operating_income: 4_000_000, net_income: 2_800_000,
          eps: 180.0, bps: 2200.0,
          operating_cf: 6_000_000, investing_cf: -2_500_000, financing_cf: -1_200_000,
        },
        metrics: {
          revenue_yoy: 0.167, operating_income_yoy: 0.333, net_income_yoy: 0.40,
          roe: 0.10, roa: 0.06, operating_margin: 0.114, net_margin: 0.08,
          free_cf: 3_500_000, per: 11.0, pbr: 1.1,
        },
      },
    ]
  end

  let(:summary) do
    s = Company::DashboardSummary.new(company: company)
    allow(s).to receive(:timeline).and_return(timeline_data)
    s
  end

  describe "#get_chart_data(:revenue_profit)" do
    it "labels と datasets が正しい構造で返る" do
      result = summary.get_chart_data(:revenue_profit)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(3)

      sales_dataset = result[:datasets][0]
      expect(sales_dataset[:label]).to eq("売上高")
      expect(sales_dataset[:type]).to eq("bar")
      expect(sales_dataset[:data]).to eq([30_000_000, 35_000_000])

      op_dataset = result[:datasets][1]
      expect(op_dataset[:label]).to eq("営業利益")
      expect(op_dataset[:type]).to eq("line")
      expect(op_dataset[:data]).to eq([3_000_000, 4_000_000])

      ni_dataset = result[:datasets][2]
      expect(ni_dataset[:label]).to eq("純利益")
      expect(ni_dataset[:type]).to eq("line")
      expect(ni_dataset[:data]).to eq([2_000_000, 2_800_000])
    end
  end

  describe "#get_chart_data(:growth_rates)" do
    it "成長率の時系列データが含まれる" do
      result = summary.get_chart_data(:growth_rates)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(3)

      expect(result[:datasets][0][:label]).to eq("売上高成長率")
      expect(result[:datasets][0][:data]).to eq([0.10, 0.167])

      expect(result[:datasets][1][:label]).to eq("営業利益成長率")
      expect(result[:datasets][1][:data]).to eq([0.15, 0.333])

      expect(result[:datasets][2][:label]).to eq("純利益成長率")
      expect(result[:datasets][2][:data]).to eq([0.12, 0.40])
    end
  end

  describe "#get_chart_data(:profitability)" do
    it "収益性指標の時系列データが含まれる" do
      result = summary.get_chart_data(:profitability)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(4)

      labels = result[:datasets].map { |d| d[:label] }
      expect(labels).to eq(["ROE", "ROA", "営業利益率", "純利益率"])

      expect(result[:datasets][0][:data]).to eq([0.08, 0.10])
    end
  end

  describe "#get_chart_data(:cashflow)" do
    it "キャッシュフローの時系列データが含まれる" do
      result = summary.get_chart_data(:cashflow)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(4)

      labels = result[:datasets].map { |d| d[:label] }
      expect(labels).to eq(["営業CF", "投資CF", "財務CF", "フリーCF"])

      expect(result[:datasets][0][:data]).to eq([5_000_000, 6_000_000])
      expect(result[:datasets][1][:data]).to eq([-2_000_000, -2_500_000])
      expect(result[:datasets][3][:data]).to eq([3_000_000, 3_500_000])
    end
  end

  describe "#get_chart_data(:valuation)" do
    it "PER/PBRの時系列データが含まれる" do
      result = summary.get_chart_data(:valuation)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(2)
      expect(result[:datasets][0][:label]).to eq("PER")
      expect(result[:datasets][0][:data]).to eq([12.5, 11.0])
      expect(result[:datasets][1][:label]).to eq("PBR")
      expect(result[:datasets][1][:data]).to eq([1.2, 1.1])
    end
  end

  describe "#get_chart_data(:per_share)" do
    it "EPS/BPSの時系列データが含まれる" do
      result = summary.get_chart_data(:per_share)

      expect(result[:labels]).to eq(["2023/3", "2024/3"])
      expect(result[:datasets].length).to eq(2)
      expect(result[:datasets][0][:label]).to eq("EPS")
      expect(result[:datasets][0][:data]).to eq([150.0, 180.0])
      expect(result[:datasets][1][:label]).to eq("BPS")
      expect(result[:datasets][1][:data]).to eq([2000.0, 2200.0])
    end
  end

  describe "#get_chart_data(:stock_price)" do
    it "株価データが空の場合、空構造を返す" do
      allow(summary).to receive(:recent_quotes).and_return([])

      result = summary.get_chart_data(:stock_price)

      expect(result[:labels]).to eq([])
      expect(result[:datasets]).to eq([])
    end
  end

  describe "#get_chart_data with timeline empty" do
    it "timelineが空の場合、空のlabelsとdatasetsを返す" do
      allow(summary).to receive(:timeline).and_return([])

      result = summary.get_chart_data(:revenue_profit)

      expect(result[:labels]).to eq([])
      expect(result[:datasets].length).to eq(3)
      result[:datasets].each do |ds|
        expect(ds[:data]).to eq([])
      end
    end
  end

  describe "#get_sector_position" do
    let(:metric) do
      FinancialMetric.new(
        roe: 0.12,
        roa: 0.06,
        operating_margin: 0.10,
        revenue_yoy: 0.15,
        data_json: { "per" => 15.0, "pbr" => 1.5, "dividend_yield" => 0.02 }
      )
    end

    let(:sector_stats_data) do
      {
        "roe" => { "mean" => 0.08, "median" => 0.07, "q1" => 0.04, "q3" => 0.12, "min" => -0.05, "max" => 0.25, "stddev" => 0.06, "count" => 50 },
        "roa" => { "mean" => 0.04, "median" => 0.035, "q1" => 0.02, "q3" => 0.06, "min" => -0.03, "max" => 0.15, "stddev" => 0.03, "count" => 50 },
        "operating_margin" => { "mean" => 0.08, "median" => 0.07, "q1" => 0.04, "q3" => 0.11, "min" => -0.02, "max" => 0.30, "stddev" => 0.05, "count" => 50 },
        "revenue_yoy" => { "mean" => 0.05, "median" => 0.04, "q1" => -0.02, "q3" => 0.10, "min" => -0.30, "max" => 0.50, "stddev" => 0.10, "count" => 50 },
        "per" => { "mean" => 20.0, "median" => 18.0, "q1" => 12.0, "q3" => 25.0, "min" => 5.0, "max" => 80.0, "stddev" => 12.0, "count" => 50 },
        "pbr" => { "mean" => 1.8, "median" => 1.5, "q1" => 1.0, "q3" => 2.2, "min" => 0.3, "max" => 8.0, "stddev" => 1.2, "count" => 50 },
        "dividend_yield" => { "mean" => 0.025, "median" => 0.02, "q1" => 0.01, "q3" => 0.035, "min" => 0.0, "max" => 0.08, "stddev" => 0.015, "count" => 50 },
      }
    end

    it "セクター内相対ポジションが正しく計算される" do
      allow(summary).to receive(:latest_financial_metric).and_return(metric)
      allow(summary).to receive(:sector_stats).and_return(sector_stats_data)

      position = summary.get_sector_position

      expect(position.keys).to include(:roe, :roa, :operating_margin, :revenue_yoy, :per, :pbr, :dividend_yield)

      roe_pos = position[:roe]
      expect(roe_pos[:value]).to eq(0.12)
      expect(roe_pos[:sector_mean]).to eq(0.08)
      expect(roe_pos[:sector_median]).to eq(0.07)
      expect(roe_pos[:percentile]).to be_a(Hash)
      expect(roe_pos[:percentile][:quartile]).to eq(3)
    end

    it "セクター統計がない場合に空Hashを返す" do
      allow(summary).to receive(:latest_financial_metric).and_return(metric)
      allow(summary).to receive(:sector_stats).and_return(nil)

      position = summary.get_sector_position

      expect(position).to eq({})
    end

    it "最新指標がない場合に空Hashを返す" do
      allow(summary).to receive(:latest_financial_metric).and_return(nil)
      allow(summary).to receive(:sector_stats).and_return(sector_stats_data)

      position = summary.get_sector_position

      expect(position).to eq({})
    end
  end

  describe "#format_fiscal_label" do
    it "日付を 年/月 形式でフォーマットする" do
      result = summary.format_fiscal_label(Date.new(2024, 3, 31))
      expect(result).to eq("2024/3")
    end

    it "nilの場合nilを返す" do
      result = summary.format_fiscal_label(nil)
      expect(result).to be_nil
    end
  end

  describe "#read_metric_value" do
    it "存在する属性の値を返す" do
      metric = FinancialMetric.new(roe: 0.12)
      result = summary.read_metric_value(metric, :roe)
      expect(result).to eq(0.12)
    end

    it "存在しないメソッドの場合nilを返す" do
      metric = FinancialMetric.new
      result = summary.read_metric_value(metric, :nonexistent_method_xyz)
      expect(result).to be_nil
    end
  end
end
