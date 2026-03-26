require "rails_helper"

RSpec.describe JquantsApi do
  describe "Faradayスタブによるユニットテスト" do
    let(:api_key) { "test_api_key" }
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:client) do
      client = JquantsApi.new(api_key: api_key)
      test_connection = Faraday.new(url: JquantsApi::BASE_URL) do |conn|
        conn.headers["x-api-key"] = api_key
        conn.adapter :test, stubs
      end
      client.instance_variable_set(:@connection, test_connection)
      client
    end

    after { stubs.verify_stubbed_calls }

    describe "#load_listed_info" do
      it "上場銘柄一覧を取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "CoName" => "日本取引所グループ" }
          ]
        }.to_json

        stubs.get("/v2/equities/master") do |env|
          expect(env.request_headers["x-api-key"]).to eq(api_key)
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_listed_info
        expect(result).to be_an(Array)
        expect(result.first["Code"]).to eq("86970")
      end

      it "codeパラメータを指定できる" do
        response_body = { "data" => [{ "Code" => "72030" }] }.to_json

        stubs.get("/v2/equities/master") do |env|
          expect(env.params["code"]).to eq("72030")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_listed_info(code: "72030")
        expect(result.first["Code"]).to eq("72030")
      end
    end

    describe "#load_daily_quotes" do
      it "株価四本値を取得できる" do
        response_body = {
          "data" => [
            { "Date" => "2024-01-15", "Code" => "72030", "O" => 2500.0, "C" => 2520.0 }
          ]
        }.to_json

        stubs.get("/v2/equities/bars/daily") do |env|
          expect(env.params["code"]).to eq("72030")
          expect(env.params["from"]).to eq("20240101")
          expect(env.params["to"]).to eq("20240131")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_daily_quotes(code: "72030", from: "20240101", to: "20240131")
        expect(result).to be_an(Array)
        expect(result.first["O"]).to eq(2500.0)
      end
    end

    describe "#load_financial_statements" do
      it "財務情報サマリーを取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "Sales" => "100529000000", "CurPerType" => "3Q" }
          ]
        }.to_json

        stubs.get("/v2/fins/summary") do |env|
          expect(env.params["code"]).to eq("86970")
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_financial_statements(code: "86970")
        expect(result.first["Sales"]).to eq("100529000000")
      end
    end

    describe "#load_earnings_calendar" do
      it "決算発表予定日を取得できる" do
        response_body = {
          "data" => [
            { "Code" => "86970", "Date" => "2024-04-30" }
          ]
        }.to_json

        stubs.get("/v2/equities/earnings-calendar") do |env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_earnings_calendar(date: "20240430")
        expect(result).to be_an(Array)
        expect(result.first["Code"]).to eq("86970")
      end
    end

    describe "#load_all_pages" do
      it "ページネーションを自動処理して全データを結合する" do
        page1_body = {
          "data" => [{ "Code" => "10000" }],
          "pagination_key" => "next_page_key"
        }.to_json

        page2_body = {
          "data" => [{ "Code" => "20000" }]
        }.to_json

        call_count = 0
        stubs.get("/v2/equities/master") do |env|
          call_count += 1
          if call_count == 1
            expect(env.params).not_to have_key("pagination_key")
            [200, { "Content-Type" => "application/json" }, page1_body]
          else
            expect(env.params["pagination_key"]).to eq("next_page_key")
            [200, { "Content-Type" => "application/json" }, page2_body]
          end
        end

        result = client.load_all_pages("equities/master")
        expect(result.length).to eq(2)
        expect(result.map { |r| r["Code"] }).to eq(["10000", "20000"])
      end

      it "pagination_keyがない場合は1ページで終了する" do
        response_body = { "data" => [{ "Code" => "10000" }] }.to_json

        stubs.get("/v2/equities/master") do
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = client.load_all_pages("equities/master")
        expect(result.length).to eq(1)
      end
    end

    describe "429レート制限のリトライ" do
      it "429レスポンスをリトライして成功する" do
        retry_client = JquantsApi.new(api_key: api_key)
        retry_stubs = Faraday::Adapter::Test::Stubs.new

        call_count = 0
        retry_stubs.get("/v2/fins/summary") do
          call_count += 1
          if call_count == 1
            [429, { "Content-Type" => "application/json" }, "Rate limit exceeded"]
          else
            [200, { "Content-Type" => "application/json" },
             { "data" => [{ "Code" => "86970" }] }.to_json]
          end
        end

        retry_connection = Faraday.new(url: JquantsApi::BASE_URL) do |conn|
          conn.headers["x-api-key"] = api_key
          conn.request :retry,
            max: 4,
            interval: 0.01,
            backoff_factor: 2,
            exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS +
                        [Faraday::TooManyRequestsError]
          conn.response :raise_error
          conn.adapter :test, retry_stubs
        end
        retry_client.instance_variable_set(:@connection, retry_connection)

        result = retry_client.load_financial_statements(code: "86970")
        expect(result).to be_an(Array)
        expect(result.first["Code"]).to eq("86970")
        expect(call_count).to eq(2)
      end
    end

    describe "サブスクリプション範囲エラー" do
      it "400レスポンスにサブスクリプション範囲メッセージが含まれる場合SubscriptionRangeErrorを発生させる" do
        error_body = '{"message": "Your subscription covers the following dates: 2024-01-01 ~ 2026-01-01. If you want more data, please check other plans:https://jpx-jquants.com/#dataset"}'

        error_stubs = Faraday::Adapter::Test::Stubs.new
        error_stubs.get("/v2/equities/bars/daily") do
          [400, { "Content-Type" => "application/json" }, error_body]
        end

        error_client = JquantsApi.new(api_key: api_key)
        error_connection = Faraday.new(url: JquantsApi::BASE_URL) do |conn|
          conn.headers["x-api-key"] = api_key
          conn.response :raise_error
          conn.adapter :test, error_stubs
        end
        error_client.instance_variable_set(:@connection, error_connection)

        expect {
          error_client.load_daily_quotes(code: "72030", from: "20200101", to: "20240131")
        }.to raise_error(JquantsApi::SubscriptionRangeError) { |e|
          expect(e.available_from).to eq(Date.new(2024, 1, 1))
          expect(e.available_to).to eq(Date.new(2026, 1, 1))
          expect(e.message).to include("2024-01-01")
        }
      end

      it "400レスポンスにサブスクリプション範囲メッセージが含まれない場合はFaraday::BadRequestErrorのまま発生させる" do
        error_stubs = Faraday::Adapter::Test::Stubs.new
        error_stubs.get("/v2/equities/bars/daily") do
          [400, { "Content-Type" => "application/json" }, '{"message": "Invalid parameter"}']
        end

        error_client = JquantsApi.new(api_key: api_key)
        error_connection = Faraday.new(url: JquantsApi::BASE_URL) do |conn|
          conn.headers["x-api-key"] = api_key
          conn.response :raise_error
          conn.adapter :test, error_stubs
        end
        error_client.instance_variable_set(:@connection, error_connection)

        expect {
          error_client.load_daily_quotes(code: "72030", from: "20240101", to: "20240131")
        }.to raise_error(Faraday::BadRequestError)
      end
    end

    describe ".default" do
      it "credentialsのAPIキーでインスタンスを生成できる" do
        skip "credentials not configured" unless Rails.application.credentials.dig(:jquants, :api_key)
        client = JquantsApi.default
        expect(client.api_key).to eq(Rails.application.credentials.jquants.api_key)
      end
    end
  end

  describe "実API呼び出しテスト" do
    let(:api_key) do
      ENV["JQUANTS_API_KEY"] || Rails.application.credentials.dig(:jquants, :api_key)
    end

    before do
      skip "JQUANTS API key not configured" unless api_key
    end

    describe "#load_listed_info" do
      it "上場銘柄一覧を取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_listed_info(code: "86970")

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key("Code")
        expect(result.first).to have_key("CoName")
      end
    end

    describe "#load_daily_quotes" do
      it "株価四本値を取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_daily_quotes(code: "86970", from: "20240101", to: "20240110")

        expect(result).to be_an(Array)
        result.each do |quote|
          expect(quote).to have_key("Date")
          expect(quote).to have_key("C")
        end
      end
    end

    describe "#load_financial_statements" do
      it "財務情報サマリーを取得できる" do
        client = JquantsApi.new(api_key: api_key)
        result = client.load_financial_statements(code: "86970")

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key("Code")
        expect(result.first).to have_key("CurPerType")
      end
    end
  end
end
