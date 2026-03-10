require "rails_helper"

RSpec.describe ImportEdinetDocumentsJob do
  let(:job) { ImportEdinetDocumentsJob.new }

  describe "#normalize_securities_code" do
    it "4桁コードを5桁に正規化する" do
      expect(job.normalize_securities_code("7203")).to eq("72030")
    end

    it "5桁コードはそのまま返す" do
      expect(job.normalize_securities_code("72030")).to eq("72030")
    end

    it "空文字列はnilを返す" do
      expect(job.normalize_securities_code("")).to be_nil
    end

    it "nilはnilを返す" do
      expect(job.normalize_securities_code(nil)).to be_nil
    end

    it "'0'はnilを返す" do
      expect(job.normalize_securities_code("0")).to be_nil
    end

    it "前後の空白を除去して正規化する" do
      expect(job.normalize_securities_code(" 7203 ")).to eq("72030")
    end
  end

  describe "#determine_report_type" do
    it "docTypeCode 120 は annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "120" })).to eq(:annual)
    end

    it "docTypeCode 130 は annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "130" })).to eq(:annual)
    end

    it "docTypeCode 160 は semi_annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "160" })).to eq(:semi_annual)
    end

    it "docTypeCode 170 は semi_annual を返す" do
      expect(job.determine_report_type({ "docTypeCode" => "170" })).to eq(:semi_annual)
    end

    it "docTypeCode 140 は期間から四半期を判定する" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-06-30",
      }
      expect(job.determine_report_type(doc)).to eq(:q1)
    end

    it "6ヶ月の四半期報告書は q2 を返す" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-09-30",
      }
      expect(job.determine_report_type(doc)).to eq(:q2)
    end

    it "9ヶ月の四半期報告書は q3 を返す" do
      doc = {
        "docTypeCode" => "140",
        "periodStart" => "2024-04-01",
        "periodEnd" => "2024-12-31",
      }
      expect(job.determine_report_type(doc)).to eq(:q3)
    end

    it "不明なdocTypeCodeはnilを返す" do
      expect(job.determine_report_type({ "docTypeCode" => "999" })).to be_nil
    end
  end

  describe "#determine_quarter" do
    it "3ヶ月はq1を返す" do
      doc = { "periodStart" => "2024-04-01", "periodEnd" => "2024-06-30" }
      expect(job.determine_quarter(doc)).to eq(:q1)
    end

    it "6ヶ月はq2を返す" do
      doc = { "periodStart" => "2024-04-01", "periodEnd" => "2024-09-30" }
      expect(job.determine_quarter(doc)).to eq(:q2)
    end

    it "9ヶ月はq3を返す" do
      doc = { "periodStart" => "2024-04-01", "periodEnd" => "2024-12-31" }
      expect(job.determine_quarter(doc)).to eq(:q3)
    end

    it "12ヶ月はannualを返す" do
      doc = { "periodStart" => "2024-04-01", "periodEnd" => "2025-03-31" }
      expect(job.determine_quarter(doc)).to eq(:annual)
    end

    it "periodStartがnilの場合はnilを返す" do
      doc = { "periodStart" => nil, "periodEnd" => "2024-06-30" }
      expect(job.determine_quarter(doc)).to be_nil
    end

    it "periodEndがnilの場合はnilを返す" do
      doc = { "periodStart" => "2024-04-01", "periodEnd" => nil }
      expect(job.determine_quarter(doc)).to be_nil
    end

    it "不正な日付の場合はnilを返す" do
      doc = { "periodStart" => "invalid", "periodEnd" => "2024-06-30" }
      expect(job.determine_quarter(doc)).to be_nil
    end
  end
end
