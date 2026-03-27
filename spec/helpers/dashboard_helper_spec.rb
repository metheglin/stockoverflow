require "rails_helper"

RSpec.describe DashboardHelper do
  describe "#format_metric_value" do
    context "nilの場合" do
      it "'-'を返す" do
        expect(helper.format_metric_value(nil, :roe)).to eq("-")
      end
    end

    context "パーセント系フィールド" do
      it "ROEをパーセント表示に変換する" do
        expect(helper.format_metric_value(0.123, :roe)).to eq("12.3%")
      end

      it "売上高成長率をパーセント表示に変換する" do
        expect(helper.format_metric_value(0.2515, :revenue_yoy)).to eq("25.2%")
      end

      it "負の値もパーセント表示に変換する" do
        expect(helper.format_metric_value(-0.05, :operating_margin)).to eq("-5.0%")
      end
    end

    context "スコア系フィールド" do
      it "composite_scoreを小数点1桁で表示する" do
        expect(helper.format_metric_value(78.56, :composite_score)).to eq("78.6")
      end

      it "growth_scoreを小数点1桁で表示する" do
        expect(helper.format_metric_value(65.0, :growth_score)).to eq("65.0")
      end
    end

    context "整数系フィールド" do
      it "連続増収期数を整数で表示する" do
        expect(helper.format_metric_value(6, :consecutive_revenue_growth)).to eq("6")
      end

      it "連続増益期数を整数で表示する" do
        expect(helper.format_metric_value(3.0, :consecutive_profit_growth)).to eq("3")
      end
    end

    context "レシオ系フィールド" do
      it "PERを小数点2桁で表示する" do
        expect(helper.format_metric_value(15.678, :per)).to eq("15.68")
      end

      it "PBRを小数点2桁で表示する" do
        expect(helper.format_metric_value(1.2, :pbr)).to eq("1.2")
      end
    end
  end

  describe "#value_color_class" do
    it "正の値に対してvalue-positiveを返す" do
      expect(helper.value_color_class(0.05)).to eq("value-positive")
    end

    it "ゼロに対してvalue-positiveを返す" do
      expect(helper.value_color_class(0)).to eq("value-positive")
    end

    it "負の値に対してvalue-negativeを返す" do
      expect(helper.value_color_class(-0.03)).to eq("value-negative")
    end

    it "nilに対して空文字を返す" do
      expect(helper.value_color_class(nil)).to eq("")
    end
  end

  describe "#metric_range_filter_options" do
    it "METRIC_RANGE_FIELDSと同じ数のオプションを返す" do
      options = helper.metric_range_filter_options
      expect(options.size).to eq(ScreeningPreset::ConditionExecutor::METRIC_RANGE_FIELDS.size)
    end

    it "[ラベル, 値]のペアを返す" do
      options = helper.metric_range_filter_options
      roe_option = options.find { |_label, value| value == "roe" }
      expect(roe_option).to be_present
      expect(roe_option[0]).to be_a(String)
    end
  end

  describe "#data_json_range_filter_options" do
    it "DATA_JSON_RANGE_FIELDSと同じ数のオプションを返す" do
      options = helper.data_json_range_filter_options
      expect(options.size).to eq(ScreeningPreset::ConditionExecutor::DATA_JSON_RANGE_FIELDS.size)
    end
  end

  describe "#metric_boolean_filter_options" do
    it "METRIC_BOOLEAN_FIELDSと同じ数のオプションを返す" do
      options = helper.metric_boolean_filter_options
      expect(options.size).to eq(ScreeningPreset::ConditionExecutor::METRIC_BOOLEAN_FIELDS.size)
    end
  end

  describe "#company_attribute_filter_options" do
    it "COMPANY_ATTRIBUTE_FIELDSと同じ数のオプションを返す" do
      options = helper.company_attribute_filter_options
      expect(options.size).to eq(ScreeningPreset::ConditionExecutor::COMPANY_ATTRIBUTE_FIELDS.size)
    end
  end

  describe "#condition_type_options" do
    it "6種類の条件タイプを返す" do
      options = helper.condition_type_options
      expect(options.size).to eq(6)
      values = options.map(&:last)
      expect(values).to include("metric_range", "data_json_range", "metric_boolean", "company_attribute", "trend_filter", "temporal")
    end
  end

  describe "#column_label" do
    it "securities_codeに証券コードを返す" do
      expect(helper.column_label("securities_code")).to eq("証券コード")
    end

    it "nameに社名を返す" do
      expect(helper.column_label("name")).to eq("社名")
    end

    it "sector_33_nameにセクターを返す" do
      expect(helper.column_label("sector_33_name")).to eq("セクター")
    end

    it "指標フィールドにI18nラベルを返す" do
      expect(helper.column_label("roe")).to eq("ROE(自己資本利益率)")
    end
  end

  describe "#numeric_column?" do
    it "securities_codeはfalseを返す" do
      expect(helper.numeric_column?("securities_code")).to be false
    end

    it "nameはfalseを返す" do
      expect(helper.numeric_column?("name")).to be false
    end

    it "roeはtrueを返す" do
      expect(helper.numeric_column?("roe")).to be true
    end

    it "composite_scoreはtrueを返す" do
      expect(helper.numeric_column?("composite_score")).to be true
    end
  end

  describe "#format_amount" do
    it "nilの場合'-'を返す" do
      expect(helper.format_amount(nil)).to eq("-")
    end

    it "兆単位にフォーマットする" do
      expect(helper.format_amount(1_500_000_000_000)).to eq("1.5兆")
    end

    it "億単位にフォーマットする" do
      expect(helper.format_amount(350_000_000)).to eq("3.5億")
    end

    it "万単位にフォーマットする" do
      expect(helper.format_amount(50_000)).to eq("5.0万")
    end

    it "小さい数値はそのまま表示する" do
      expect(helper.format_amount(1234)).to eq("1,234")
    end

    it "負の兆単位にフォーマットする" do
      expect(helper.format_amount(-2_000_000_000_000)).to eq("-2.0兆")
    end
  end

  describe "#format_detail_percent" do
    it "nilの場合'-'を返す" do
      expect(helper.format_detail_percent(nil)).to eq("-")
    end

    it "小数をパーセント表示に変換する" do
      expect(helper.format_detail_percent(0.123)).to eq("12.3%")
    end

    it "負の値もパーセント表示に変換する" do
      expect(helper.format_detail_percent(-0.05)).to eq("-5.0%")
    end
  end

  describe "#format_detail_ratio" do
    it "nilの場合'-'を返す" do
      expect(helper.format_detail_ratio(nil)).to eq("-")
    end

    it "倍率表示に変換する" do
      expect(helper.format_detail_ratio(15.678)).to eq("15.68x")
    end
  end

  describe "#format_yoy" do
    it "nilの場合'-'を返す" do
      expect(helper.format_yoy(nil)).to eq("-")
    end

    it "正のYoYを+付きで表示する" do
      expect(helper.format_yoy(0.152)).to eq("+15.2% YoY")
    end

    it "負のYoYをマイナス付きで表示する" do
      expect(helper.format_yoy(-0.08)).to eq("-8.0% YoY")
    end
  end

  describe "#format_table_value" do
    it "nilの場合'-'を返す" do
      expect(helper.format_table_value(nil, :amount)).to eq("-")
    end

    it "amount形式でフォーマットする" do
      expect(helper.format_table_value(500_000_000, :amount)).to eq("5.0億")
    end

    it "percent形式でフォーマットする" do
      expect(helper.format_table_value(0.15, :percent)).to eq("15.0%")
    end

    it "ratio形式でフォーマットする" do
      expect(helper.format_table_value(12.5, :ratio)).to eq("12.5x")
    end

    it "number形式で整数をフォーマットする" do
      expect(helper.format_table_value(1500, :number)).to eq("1,500")
    end

    it "number形式で小数をフォーマットする" do
      expect(helper.format_table_value(12.345, :number)).to eq("12.35")
    end
  end

  describe "#get_result_value" do
    let(:company) { Company.new(securities_code: "7203", name: "トヨタ自動車", sector_33_name: "輸送用機器") }
    let(:metric) { FinancialMetric.new(roe: 0.123, revenue_yoy: 0.15) }

    it "企業属性カラムはcompanyから取得する" do
      expect(helper.get_result_value(company, metric, "securities_code")).to eq("7203")
      expect(helper.get_result_value(company, metric, "name")).to eq("トヨタ自動車")
    end

    it "指標カラムはmetricから取得する" do
      expect(helper.get_result_value(company, metric, "roe")).to eq(0.123)
      expect(helper.get_result_value(company, metric, "revenue_yoy")).to eq(0.15)
    end
  end
end
