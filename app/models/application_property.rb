class ApplicationProperty < ApplicationRecord
  include JsonAttribute

  enum :kind, {
    default: 0,
    edinet_sync: 1,
    jquants_sync: 2,
  }

  define_json_attributes :data_json, schema: {
    last_synced_at: { type: :string },
    last_synced_date: { type: :string },
    sync_cursor: { type: :string },
  }
end
