class ScreeningPreset < ApplicationRecord
  include JsonAttribute

  enum :preset_type, {
    builtin: 0,
    custom: 1,
  }

  enum :status, {
    disabled: 0,
    enabled: 1,
  }

  define_json_attributes :display_json, schema: {
    columns: { type: :array },
    sort_by: { type: :string },
    sort_order: { type: :string },
    limit: { type: :integer },
  }

  def parsed_conditions
    raw = conditions_json
    case raw
    when Hash then raw.deep_symbolize_keys
    when String then JSON.parse(raw).deep_symbolize_keys
    else {}
    end
  end

  def parsed_display
    raw = display_json
    case raw
    when Hash then raw.deep_symbolize_keys
    when String then JSON.parse(raw).deep_symbolize_keys
    else {}
    end
  end

  def record_execution!
    increment!(:execution_count)
    update!(last_executed_at: Time.current)
  end
end
