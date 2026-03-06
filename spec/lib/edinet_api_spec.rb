require "rails_helper"

RSpec.describe EdinetApi do
  describe "#load_documents" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      c = EdinetApi.new(api_key: "test-api-key")
      conn = Faraday.new(url: EdinetApi::BASE_URL) do |f|
        f.adapter :test, stubs
      end
      c.instance_variable_set(:@connection, conn)
      c
    end

    it "正しいURLにSubscription-Keyを含むリクエストを送信する" do
      requested_params = nil
      stubs.get("/api/v2/documents.json") do |env|
        requested_params = Rack::Utils.parse_query(env.url.query)
        [200, {"Content-Type" => "application/json"}, '{"metadata":{"status":"200"},"results":[]}']
      end

      client.load_documents(date: "2024-06-25")

      expect(requested_params["Subscription-Key"]).to eq("test-api-key")
      expect(requested_params["date"]).to eq("2024-06-25")
      expect(requested_params["type"]).to eq("2")
    end

    it "include_documents: falseの場合type=1を送信する" do
      requested_params = nil
      stubs.get("/api/v2/documents.json") do |env|
        requested_params = Rack::Utils.parse_query(env.url.query)
        [200, {"Content-Type" => "application/json"}, '{"metadata":{"status":"200"},"results":[]}']
      end

      client.load_documents(date: "2024-06-25", include_documents: false)

      expect(requested_params["type"]).to eq("1")
    end

    it "Date型をYYYY-MM-DD文字列に変換する" do
      requested_params = nil
      stubs.get("/api/v2/documents.json") do |env|
        requested_params = Rack::Utils.parse_query(env.url.query)
        [200, {"Content-Type" => "application/json"}, '{"metadata":{"status":"200"},"results":[]}']
      end

      client.load_documents(date: Date.new(2024, 6, 25))

      expect(requested_params["date"]).to eq("2024-06-25")
    end

    it "レスポンスJSONをパースして返す" do
      response_body = {
        "metadata" => {"status" => "200", "resultset" => {"count" => 1}},
        "results" => [{"docID" => "S100TEST"}],
      }.to_json
      stubs.get("/api/v2/documents.json") do
        [200, {"Content-Type" => "application/json"}, response_body]
      end

      result = client.load_documents(date: "2024-06-25")

      expect(result["metadata"]["status"]).to eq("200")
      expect(result["results"]).to be_an(Array)
      expect(result["results"].first["docID"]).to eq("S100TEST")
    end
  end

  describe "#load_target_documents" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      c = EdinetApi.new(api_key: "test-api-key")
      conn = Faraday.new(url: EdinetApi::BASE_URL) do |f|
        f.adapter :test, stubs
      end
      c.instance_variable_set(:@connection, conn)
      c
    end

    it "対象書類種別・xbrlFlag・withdrawalStatusで絞り込む" do
      response_body = {
        "metadata" => {"status" => "200"},
        "results" => [
          {"docID" => "S100A", "docTypeCode" => "120", "xbrlFlag" => "1", "withdrawalStatus" => "0"},
          {"docID" => "S100B", "docTypeCode" => "999", "xbrlFlag" => "1", "withdrawalStatus" => "0"},
          {"docID" => "S100C", "docTypeCode" => "120", "xbrlFlag" => "0", "withdrawalStatus" => "0"},
          {"docID" => "S100D", "docTypeCode" => "120", "xbrlFlag" => "1", "withdrawalStatus" => "1"},
          {"docID" => "S100E", "docTypeCode" => "140", "xbrlFlag" => "1", "withdrawalStatus" => "0"},
        ],
      }.to_json
      stubs.get("/api/v2/documents.json") do
        [200, {"Content-Type" => "application/json"}, response_body]
      end

      docs = client.load_target_documents(date: "2024-06-25")

      expect(docs.length).to eq(2)
      expect(docs.map { |d| d["docID"] }).to eq(%w[S100A S100E])
    end
  end

  describe "#load_xbrl_zip" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      c = EdinetApi.new(api_key: "test-api-key")
      conn = Faraday.new(url: EdinetApi::BASE_URL) do |f|
        f.adapter :test, stubs
      end
      c.instance_variable_set(:@connection, conn)
      c
    end

    it "書類IDに対応するURLにtype=1でリクエストし、Tempfileを返す" do
      zip_content = "PK\x03\x04fake-zip-data"
      requested_params = nil
      stubs.get("/api/v2/documents/S100TEST") do |env|
        requested_params = Rack::Utils.parse_query(env.url.query)
        [200, {"Content-Type" => "application/octet-stream"}, zip_content]
      end

      tempfile = client.load_xbrl_zip(doc_id: "S100TEST")

      expect(requested_params["type"]).to eq("1")
      expect(tempfile).to be_a(Tempfile)
      expect(tempfile.read).to eq(zip_content)
      tempfile.close!
    end
  end

  describe "#load_csv_zip" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      c = EdinetApi.new(api_key: "test-api-key")
      conn = Faraday.new(url: EdinetApi::BASE_URL) do |f|
        f.adapter :test, stubs
      end
      c.instance_variable_set(:@connection, conn)
      c
    end

    it "書類IDに対応するURLにtype=5でリクエストし、Tempfileを返す" do
      csv_content = "PK\x03\x04fake-csv-zip"
      requested_params = nil
      stubs.get("/api/v2/documents/S100TEST") do |env|
        requested_params = Rack::Utils.parse_query(env.url.query)
        [200, {"Content-Type" => "application/octet-stream"}, csv_content]
      end

      tempfile = client.load_csv_zip(doc_id: "S100TEST")

      expect(requested_params["type"]).to eq("5")
      expect(tempfile).to be_a(Tempfile)
      expect(tempfile.read).to eq(csv_content)
      tempfile.close!
    end
  end

  describe ".default" do
    it "credentialsのAPIキーでインスタンスを生成できる" do
      skip "credentials not configured" unless Rails.application.credentials.dig(:edinet, :api_key)
      client = EdinetApi.default
      expect(client.api_key).to eq(Rails.application.credentials.edinet.api_key)
    end
  end

  # 実APIテスト（APIキーが設定されている場合のみ実行）
  context "実API呼び出し", if: (ENV["EDINET_API_KEY"] || Rails.application.credentials.dig(:edinet, :api_key)) do
    let(:api_key) { ENV["EDINET_API_KEY"] || Rails.application.credentials.dig(:edinet, :api_key) }

    it "指定日の書類一覧を取得できる" do
      client = EdinetApi.new(api_key: api_key)
      result = client.load_documents(date: "2024-06-25", include_documents: true)

      expect(result).to have_key("metadata")
      expect(result).to have_key("results")
      expect(result["metadata"]["status"]).to eq("200")
      expect(result["results"]).to be_an(Array)
    end
  end
end
