require "rails_helper"

RSpec.describe EdinetApi do
  # credentialsにAPIキーが設定されている場合のみ実行
  # EDINET_API_KEY 環境変数でのオーバーライドも可能
  let(:api_key) do
    ENV["EDINET_API_KEY"] || Rails.application.credentials.dig(:edinet, :api_key)
  end

  before do
    skip "EDINET API key not configured" unless api_key
  end

  describe "#load_documents" do
    it "指定日の書類一覧を取得できる" do
      client = EdinetApi.new(api_key: api_key)
      result = client.load_documents(date: "2024-06-25", include_documents: true)

      expect(result).to have_key("metadata")
      expect(result).to have_key("results")
      expect(result["metadata"]["status"]).to eq("200")
      expect(result["results"]).to be_an(Array)
    end

    it "Date型でも指定できる" do
      client = EdinetApi.new(api_key: api_key)
      result = client.load_documents(date: Date.new(2024, 6, 25))

      expect(result["metadata"]["status"]).to eq("200")
    end
  end

  describe "#load_target_documents" do
    it "対象書類種別のみに絞り込まれる" do
      client = EdinetApi.new(api_key: api_key)
      docs = client.load_target_documents(date: "2024-06-25")

      expect(docs).to be_an(Array)
      docs.each do |doc|
        expect(EdinetApi::TARGET_DOC_TYPE_CODES).to include(doc["docTypeCode"])
        expect(doc["xbrlFlag"]).to eq("1")
        expect(doc["withdrawalStatus"]).to eq("0")
      end
    end
  end

  describe ".default" do
    it "credentialsのAPIキーでインスタンスを生成できる" do
      skip "credentials not configured" unless Rails.application.credentials.dig(:edinet, :api_key)
      client = EdinetApi.default
      expect(client.api_key).to eq(Rails.application.credentials.edinet.api_key)
    end
  end
end
