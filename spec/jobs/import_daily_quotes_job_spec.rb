require "rails_helper"

RSpec.describe ImportDailyQuotesJob do
  let(:job) { ImportDailyQuotesJob.new }

  describe "#clamp_date_range" do
    it "開始日をサブスクリプション開始日にクランプする" do
      from = Date.new(2020, 1, 1)
      to = Date.new(2026, 3, 26)
      error = JquantsApi::SubscriptionRangeError.new(
        "subscription error",
        available_from: Date.new(2024, 1, 1),
        available_to: Date.new(2026, 3, 26)
      )

      result_from, result_to = job.send(:clamp_date_range, from, to, error)

      expect(result_from).to eq(Date.new(2024, 1, 1))
      expect(result_to).to eq(Date.new(2026, 3, 26))
    end

    it "終了日をサブスクリプション終了日にクランプする" do
      from = Date.new(2024, 1, 1)
      to = Date.new(2026, 12, 31)
      error = JquantsApi::SubscriptionRangeError.new(
        "subscription error",
        available_from: Date.new(2024, 1, 1),
        available_to: Date.new(2026, 3, 26)
      )

      result_from, result_to = job.send(:clamp_date_range, from, to, error)

      expect(result_from).to eq(Date.new(2024, 1, 1))
      expect(result_to).to eq(Date.new(2026, 3, 26))
    end

    it "両端をクランプする" do
      from = Date.new(2020, 1, 1)
      to = Date.new(2030, 12, 31)
      error = JquantsApi::SubscriptionRangeError.new(
        "subscription error",
        available_from: Date.new(2024, 1, 1),
        available_to: Date.new(2026, 3, 26)
      )

      result_from, result_to = job.send(:clamp_date_range, from, to, error)

      expect(result_from).to eq(Date.new(2024, 1, 1))
      expect(result_to).to eq(Date.new(2026, 3, 26))
    end

    it "範囲内の場合はそのまま返す" do
      from = Date.new(2025, 1, 1)
      to = Date.new(2025, 6, 30)
      error = JquantsApi::SubscriptionRangeError.new(
        "subscription error",
        available_from: Date.new(2024, 1, 1),
        available_to: Date.new(2026, 3, 26)
      )

      result_from, result_to = job.send(:clamp_date_range, from, to, error)

      expect(result_from).to eq(Date.new(2025, 1, 1))
      expect(result_to).to eq(Date.new(2025, 6, 30))
    end
  end

  describe "#parse_date" do
    it "有効な日付文字列をDateオブジェクトに変換する" do
      expect(job.send(:parse_date, "2024-01-15")).to eq(Date.new(2024, 1, 15))
    end

    it "nilの場合はnilを返す" do
      expect(job.send(:parse_date, nil)).to be_nil
    end

    it "空文字列の場合はnilを返す" do
      expect(job.send(:parse_date, "")).to be_nil
    end

    it "不正な日付文字列の場合はnilを返す" do
      expect(job.send(:parse_date, "invalid")).to be_nil
    end
  end

  describe "import_full retry behavior" do
    let(:client) { instance_double(JquantsApi) }
    let(:subscription_error) do
      JquantsApi::SubscriptionRangeError.new(
        "subscription error",
        available_from: Date.new(2024, 1, 1),
        available_to: Date.new(2026, 3, 26)
      )
    end

    before do
      job.instance_variable_set(:@client, client)
      job.instance_variable_set(:@stats, { imported: 0, skipped: 0, errors: 0 })
      job.instance_variable_set(:@subscription_errors, 0)
    end

    def stub_companies(*companies)
      scope = double("scope")
      allow(Company).to receive(:listed).and_return(scope)
      where_scope = double("where_scope")
      allow(scope).to receive(:where).and_return(where_scope)
      not_scope = double("not_scope")
      allow(where_scope).to receive(:not).with(securities_code: nil).and_return(not_scope)
      yielder = allow(not_scope).to receive(:find_each)
      companies.each { |c| yielder = yielder.and_yield(c) }
    end

    it "SubscriptionRangeError発生時、日付をクランプして1回だけリトライする" do
      company = Company.new(securities_code: "12340", listed: true)
      stub_companies(company)
      allow(job).to receive(:sleep)

      call_count = 0
      allow(client).to receive(:load_daily_quotes) do |**args|
        call_count += 1
        if call_count == 1
          raise subscription_error
        end
        []
      end

      job.send(:import_full)

      expect(call_count).to eq(2)
    end

    it "リトライ後もSubscriptionRangeError発生時、スキップして次の企業に進む" do
      company = Company.new(securities_code: "12340", listed: true)
      stub_companies(company)
      allow(job).to receive(:sleep)

      allow(client).to receive(:load_daily_quotes).and_raise(subscription_error)

      expect { job.send(:import_full) }.not_to raise_error

      expect(job.instance_variable_get(:@stats)[:errors]).to eq(1)
    end

    it "複数企業でSubscriptionRangeErrorが発生してもジョブ全体は中断しない" do
      company_a = Company.new(securities_code: "11110", listed: true)
      company_b = Company.new(securities_code: "22220", listed: true)
      company_c = Company.new(securities_code: "33330", listed: true)
      stub_companies(company_a, company_b, company_c)
      allow(job).to receive(:sleep)

      allow(client).to receive(:load_daily_quotes).and_raise(subscription_error)

      expect { job.send(:import_full) }.not_to raise_error

      expect(job.instance_variable_get(:@stats)[:errors]).to eq(3)
    end

    it "1つ目の企業でクランプ後、2つ目以降はクランプ済み日付を使用する" do
      company_a = Company.new(securities_code: "11110", listed: true)
      company_b = Company.new(securities_code: "22220", listed: true)
      stub_companies(company_a, company_b)
      allow(job).to receive(:sleep)

      recorded_from_dates = []
      call_count = 0
      allow(client).to receive(:load_daily_quotes) do |**args|
        call_count += 1
        recorded_from_dates << args[:from]
        if call_count == 1
          raise subscription_error
        end
        []
      end

      job.send(:import_full)

      # 1回目: 2020-01-01(デフォルト), 2回目: クランプ後(2024-01-01), 3回目: クランプ済み(2024-01-01)
      expect(recorded_from_dates[0]).to eq("20200101")
      expect(recorded_from_dates[1]).to eq("20240101")
      expect(recorded_from_dates[2]).to eq("20240101")
    end
  end
end
