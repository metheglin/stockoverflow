require "rails_helper"

RSpec.describe ApplicationProperty do
  describe ".get_sync_staleness" do
    let(:reference_date) { Date.new(2026, 3, 16) }

    it "同期日が閾値以内の場合はstale: falseを返す" do
      result = ApplicationProperty.get_sync_staleness(
        "2026-03-14",
        reference_date: reference_date,
      )

      expect(result[:stale]).to eq(false)
      expect(result[:days_since_sync]).to eq(2)
    end

    it "同期日が閾値を超える場合はstale: trueを返す" do
      result = ApplicationProperty.get_sync_staleness(
        "2026-03-10",
        reference_date: reference_date,
      )

      expect(result[:stale]).to eq(true)
      expect(result[:days_since_sync]).to eq(6)
    end

    it "同期日がちょうど閾値の場合はstale: falseを返す" do
      result = ApplicationProperty.get_sync_staleness(
        "2026-03-13",
        reference_date: reference_date,
        threshold_days: 3,
      )

      expect(result[:stale]).to eq(false)
      expect(result[:days_since_sync]).to eq(3)
    end

    it "同期日がnilの場合はstale: trueでdays_since_syncがnilを返す" do
      result = ApplicationProperty.get_sync_staleness(
        nil,
        reference_date: reference_date,
      )

      expect(result[:stale]).to eq(true)
      expect(result[:days_since_sync]).to be_nil
    end

    it "同期日がDate型の場合も正しく判定する" do
      result = ApplicationProperty.get_sync_staleness(
        Date.new(2026, 3, 15),
        reference_date: reference_date,
      )

      expect(result[:stale]).to eq(false)
      expect(result[:days_since_sync]).to eq(1)
    end

    it "カスタム閾値を指定できる" do
      result = ApplicationProperty.get_sync_staleness(
        "2026-03-10",
        reference_date: reference_date,
        threshold_days: 7,
      )

      expect(result[:stale]).to eq(false)
      expect(result[:days_since_sync]).to eq(6)
    end
  end
end
