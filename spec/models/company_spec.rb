require "rails_helper"

RSpec.describe Company do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Date" => "2024-01-15",
        "Code" => "86970",
        "CoName" => "日本取引所グループ",
        "CoNameEn" => "Japan Exchange Group,Inc.",
        "S17" => "16",
        "S17Nm" => "金融（除く銀行）",
        "S33" => "7200",
        "S33Nm" => "その他金融業",
        "ScaleCat" => "TOPIX Large70",
        "Mkt" => "0111",
        "MktNm" => "プライム",
        "Mrgn" => "1",
        "MrgnNm" => "貸借",
      }
    end

    it "JQUANTSレスポンスからCompany属性Hashを生成できる" do
      attrs = Company.get_attributes_from_jquants(jquants_data)

      expect(attrs[:securities_code]).to eq("86970")
      expect(attrs[:name]).to eq("日本取引所グループ")
      expect(attrs[:name_english]).to eq("Japan Exchange Group,Inc.")
      expect(attrs[:sector_17_code]).to eq("16")
      expect(attrs[:sector_17_name]).to eq("金融（除く銀行）")
      expect(attrs[:sector_33_code]).to eq("7200")
      expect(attrs[:sector_33_name]).to eq("その他金融業")
      expect(attrs[:scale_category]).to eq("TOPIX Large70")
      expect(attrs[:market_code]).to eq("0111")
      expect(attrs[:market_name]).to eq("プライム")
      expect(attrs[:listed]).to eq(true)
    end

    it "data_jsonフィールドが正しく設定される" do
      attrs = Company.get_attributes_from_jquants(jquants_data)

      expect(attrs[:data_json]).to include("mrgn" => "1", "mrgn_nm" => "貸借")
    end

    it "キーが存在しない場合はスキップされる" do
      attrs = Company.get_attributes_from_jquants({ "Code" => "12340", "CoName" => "テスト" })

      expect(attrs[:securities_code]).to eq("12340")
      expect(attrs[:name]).to eq("テスト")
      expect(attrs).not_to have_key(:name_english)
    end
  end
end
