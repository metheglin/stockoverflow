require "rails_helper"

RSpec.describe FinancialValue do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Code" => "86970",
        "CurPerType" => "FY",
        "Sales" => "100529000000",
        "OP" => "50000000000",
        "OdP" => "52000000000",
        "NP" => "35000000000",
        "EPS" => "66.76",
        "DEPS" => "66.50",
        "TA" => "500000000000",
        "Eq" => "200000000000",
        "EqRatio" => "40.0",
        "BPS" => "380.50",
        "CFO" => "60000000000",
        "CFI" => "-20000000000",
        "CFF" => "-15000000000",
        "CashEq" => "80000000000",
        "ShOutFY" => "524000000",
        "TrShFY" => "10000000",
        "DivAnn" => "50.0",
        "FSales" => "110000000000",
        "FOP" => "55000000000",
        "FOdP" => "56000000000",
        "FNP" => "38000000000",
        "FEPS" => "72.50",
        "NCSales" => "80000000000",
        "NCOP" => "40000000000",
        "NCOdP" => "42000000000",
        "NCNP" => "28000000000",
        "NCEPS" => "53.40",
        "NCTA" => "400000000000",
        "NCEq" => "180000000000",
        "NCBPS" => "343.00",
      }
    end

    context "連結データ" do
      it "固定カラムの属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :consolidated)

        expect(attrs[:net_sales]).to eq(100529000000)
        expect(attrs[:operating_income]).to eq(50000000000)
        expect(attrs[:ordinary_income]).to eq(52000000000)
        expect(attrs[:net_income]).to eq(35000000000)
        expect(attrs[:eps]).to eq(BigDecimal("66.76"))
        expect(attrs[:diluted_eps]).to eq(BigDecimal("66.50"))
        expect(attrs[:total_assets]).to eq(500000000000)
        expect(attrs[:net_assets]).to eq(200000000000)
        expect(attrs[:equity_ratio]).to eq(BigDecimal("40.0"))
        expect(attrs[:bps]).to eq(BigDecimal("380.50"))
        expect(attrs[:operating_cf]).to eq(60000000000)
        expect(attrs[:investing_cf]).to eq(-20000000000)
        expect(attrs[:financing_cf]).to eq(-15000000000)
        expect(attrs[:cash_and_equivalents]).to eq(80000000000)
        expect(attrs[:shares_outstanding]).to eq(524000000)
        expect(attrs[:treasury_shares]).to eq(10000000)
      end

      it "data_jsonの属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :consolidated)

        expect(attrs[:data_json]["dividend_per_share_annual"]).to eq(50.0)
        expect(attrs[:data_json]["forecast_net_sales"]).to eq(110000000000)
        expect(attrs[:data_json]["forecast_operating_income"]).to eq(55000000000)
      end

      it "空文字列はnilに変換される" do
        data = jquants_data.merge("Sales" => "", "OP" => nil)
        attrs = FinancialValue.get_attributes_from_jquants(data, scope_type: :consolidated)

        expect(attrs[:net_sales]).to be_nil
        expect(attrs[:operating_income]).to be_nil
      end
    end

    context "個別データ" do
      it "NC*フィールドから属性が正しく変換される" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :non_consolidated)

        expect(attrs[:net_sales]).to eq(80000000000)
        expect(attrs[:operating_income]).to eq(40000000000)
        expect(attrs[:ordinary_income]).to eq(42000000000)
        expect(attrs[:net_income]).to eq(28000000000)
        expect(attrs[:eps]).to eq(BigDecimal("53.40"))
        expect(attrs[:total_assets]).to eq(400000000000)
        expect(attrs[:net_assets]).to eq(180000000000)
        expect(attrs[:bps]).to eq(BigDecimal("343.00"))
      end

      it "data_jsonは設定されない" do
        attrs = FinancialValue.get_attributes_from_jquants(jquants_data, scope_type: :non_consolidated)

        expect(attrs).not_to have_key(:data_json)
      end
    end
  end

  describe ".parse_jquants_value" do
    it "整数カラムの場合はIntegerに変換する" do
      expect(FinancialValue.parse_jquants_value("100529000000", :net_sales)).to eq(100529000000)
    end

    it "小数カラムの場合はBigDecimalに変換する" do
      expect(FinancialValue.parse_jquants_value("66.76", :eps)).to eq(BigDecimal("66.76"))
    end

    it "空文字列はnilを返す" do
      expect(FinancialValue.parse_jquants_value("", :net_sales)).to be_nil
    end

    it "nilはnilを返す" do
      expect(FinancialValue.parse_jquants_value(nil, :net_sales)).to be_nil
    end

    it "負の値を正しく変換する" do
      expect(FinancialValue.parse_jquants_value("-20000000000", :investing_cf)).to eq(-20000000000)
    end
  end
end
