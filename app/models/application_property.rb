class ApplicationProperty < ApplicationRecord
  include JsonAttribute

  SYNC_STALE_THRESHOLD_DAYS = 3

  enum :kind, {
    default: 0,
    edinet_sync: 1,
    jquants_sync: 2,
    data_integrity: 3,
  }

  define_json_attributes :data_json, schema: {
    last_synced_at: { type: :string },
    last_synced_date: { type: :string },
    sync_cursor: { type: :string },
  }

  # 同期日の鮮度を判定する
  #
  # @param last_synced_date [String, Date, nil] 最終同期日
  # @param reference_date [Date] 基準日（通常はDate.current）
  # @param threshold_days [Integer] 古いとみなす閾値（日数）
  # @return [Hash] { stale: Boolean, days_since_sync: Integer or nil }
  #
  # 例:
  #   ApplicationProperty.get_sync_staleness("2026-03-10", reference_date: Date.new(2026, 3, 16))
  #   # => { stale: true, days_since_sync: 6 }
  #
  def self.get_sync_staleness(last_synced_date, reference_date:, threshold_days: SYNC_STALE_THRESHOLD_DAYS)
    return { stale: true, days_since_sync: nil } if last_synced_date.nil?

    synced = last_synced_date.is_a?(Date) ? last_synced_date : Date.parse(last_synced_date.to_s)
    days = (reference_date - synced).to_i

    { stale: days > threshold_days, days_since_sync: days }
  end
end
