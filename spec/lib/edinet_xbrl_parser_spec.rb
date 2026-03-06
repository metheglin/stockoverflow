require "rails_helper"

RSpec.describe EdinetXbrlParser do
  describe "#parse" do
    context "テスト用XBRLフィクスチャが存在する場合" do
      let(:fixture_zip_path) { Rails.root.join("spec/fixtures/edinet/sample_xbrl.zip") }

      before do
        skip "XBRLフィクスチャが未配置" unless File.exist?(fixture_zip_path)
      end

      it "連結財務数値を抽出できる" do
        parser = EdinetXbrlParser.new(zip_path: fixture_zip_path.to_s)
        result = parser.parse

        expect(result).to have_key(:consolidated)
        consolidated = result[:consolidated]
        # 売上高・営業利益・総資産のいずれかが取得できていること
        expect(
          consolidated[:net_sales] || consolidated[:operating_income] || consolidated[:total_assets]
        ).not_to be_nil
      end
    end
  end

  describe "#find_element_value" do
    it "XBRLドキュメントから指定要素の値を抽出できる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">1234567890</jppfs_cor:NetSales>
          <jppfs_cor:Assets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">9876543210</jppfs_cor:Assets>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      # P/L項目（duration context）
      mapping = { elements: ["NetSales"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(1_234_567_890)

      # B/S項目（instant context）
      mapping = { elements: ["Assets"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearInstant\z/)
      expect(value).to eq(9_876_543_210)
    end

    it "候補配列の先頭要素が見つからない場合、次の候補を検索する" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:OperatingRevenue1 contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">5000000000</jppfs_cor:OperatingRevenue1>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      # NetSalesがない場合、OperatingRevenue1を検索
      mapping = { elements: ["NetSales", "OperatingRevenue1"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(5_000_000_000)
    end

    it "該当する要素がない場合nilを返す" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance">
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      mapping = { elements: ["NetSales"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to be_nil
    end

    it "マイナス値を正しく変換できる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetCashProvidedByUsedInInvestmentActivities contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">-500000000</jppfs_cor:NetCashProvidedByUsedInInvestmentActivities>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      mapping = { elements: ["NetCashProvidedByUsedInInvestmentActivities"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(-500_000_000)
    end

    it "コンテキストIDが一致しない要素はスキップする" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="Prior1YearDuration" unitRef="JPY" decimals="0">1000000000</jppfs_cor:NetSales>
          <jppfs_cor:NetSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">1200000000</jppfs_cor:NetSales>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      mapping = { elements: ["NetSales"], namespace: "jppfs_cor" }
      value = parser.find_element_value(doc, mapping, /\ACurrentYearDuration\z/)
      expect(value).to eq(1_200_000_000)
    end
  end

  describe "#extract_values" do
    it "連結の財務数値を正しく抽出できる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">10000000000</jppfs_cor:NetSales>
          <jppfs_cor:OperatingIncome contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">1000000000</jppfs_cor:OperatingIncome>
          <jppfs_cor:Assets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">20000000000</jppfs_cor:Assets>
          <jppfs_cor:NetAssets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">8000000000</jppfs_cor:NetAssets>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      result = parser.extract_values(doc, scope: :consolidated)
      expect(result[:net_sales]).to eq(10_000_000_000)
      expect(result[:operating_income]).to eq(1_000_000_000)
      expect(result[:total_assets]).to eq(20_000_000_000)
      expect(result[:net_assets]).to eq(8_000_000_000)
      expect(result[:extended]).to be_a(Hash)
    end

    it "個別の財務数値を正しく抽出できる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="CurrentYearDuration_NonConsolidatedMember" unitRef="JPY" decimals="0">5000000000</jppfs_cor:NetSales>
          <jppfs_cor:Assets contextRef="CurrentYearInstant_NonConsolidatedMember" unitRef="JPY" decimals="0">15000000000</jppfs_cor:Assets>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      result = parser.extract_values(doc, scope: :non_consolidated)
      expect(result[:net_sales]).to eq(5_000_000_000)
      expect(result[:total_assets]).to eq(15_000_000_000)
    end

    it "主要3項目がすべてnilの場合nilを返す" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance">
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      result = parser.extract_values(doc, scope: :consolidated)
      expect(result).to be_nil
    end

    it "拡張要素がextendedキーに格納される" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xbrli:xbrl
          xmlns:xbrli="http://www.xbrl.org/2003/instance"
          xmlns:jppfs_cor="http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor">
          <jppfs_cor:NetSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">10000000000</jppfs_cor:NetSales>
          <jppfs_cor:CostOfSales contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">6000000000</jppfs_cor:CostOfSales>
          <jppfs_cor:GrossProfit contextRef="CurrentYearDuration" unitRef="JPY" decimals="0">4000000000</jppfs_cor:GrossProfit>
          <jppfs_cor:CurrentAssets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">12000000000</jppfs_cor:CurrentAssets>
          <jppfs_cor:Assets contextRef="CurrentYearInstant" unitRef="JPY" decimals="0">20000000000</jppfs_cor:Assets>
        </xbrli:xbrl>
      XML

      doc = Nokogiri::XML(xml)
      parser = EdinetXbrlParser.new(zip_path: "dummy")

      result = parser.extract_values(doc, scope: :consolidated)
      expect(result[:extended][:cost_of_sales]).to eq(6_000_000_000)
      expect(result[:extended][:gross_profit]).to eq(4_000_000_000)
      expect(result[:extended][:current_assets]).to eq(12_000_000_000)
    end
  end
end
