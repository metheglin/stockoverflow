BUILTIN_PRESETS = [
  {
    name: "連続増収増益（6期以上）",
    description: "6期以上連続で増収増益を達成している企業を一覧する",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "metric_range", field: "consecutive_revenue_growth", min: 6 },
        { type: "metric_range", field: "consecutive_profit_growth", min: 6 },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name consecutive_revenue_growth consecutive_profit_growth revenue_yoy operating_income_yoy],
      sort_by: "revenue_yoy", sort_order: "desc", limit: 100,
    },
  },
  {
    name: "高ROE・低PBR バリュー",
    description: "ROE10%以上かつPBR1.5倍以下で営業CFがプラスの企業",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "metric_range", field: "roe", min: 0.10 },
        { type: "data_json_range", field: "pbr", max: 1.5 },
        { type: "metric_boolean", field: "operating_cf_positive", value: true },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name roe pbr operating_margin],
      sort_by: "roe", sort_order: "desc", limit: 100,
    },
  },
  {
    name: "高成長グロース",
    description: "売上・営業利益ともにYoY15%以上の高成長企業",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "metric_range", field: "revenue_yoy", min: 0.15 },
        { type: "metric_range", field: "operating_income_yoy", min: 0.15 },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name revenue_yoy operating_income_yoy composite_score],
      sort_by: "revenue_yoy", sort_order: "desc", limit: 100,
    },
  },
  {
    name: "FCF プラス転換",
    description: "営業CFプラス・投資CFマイナスかつFCFがプラスの企業",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "metric_boolean", field: "operating_cf_positive", value: true },
        { type: "metric_boolean", field: "investing_cf_negative", value: true },
        { type: "metric_boolean", field: "free_cf_positive", value: true },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name free_cf operating_margin roe],
      sort_by: "roe", sort_order: "desc", limit: 100,
    },
  },
  {
    name: "高配当利回り",
    description: "配当利回り3%以上かつ営業CFプラスの企業",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "data_json_range", field: "dividend_yield", min: 0.03 },
        { type: "metric_boolean", field: "operating_cf_positive", value: true },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name dividend_yield roe operating_margin],
      sort_by: "roe", sort_order: "desc", limit: 100,
    },
  },
  {
    name: "総合スコアTOP100",
    description: "複合スコア上位100社",
    conditions_json: {
      scope_type: "consolidated", period_type: "annual", logic: "and",
      conditions: [
        { type: "metric_top_n", field: "composite_score", direction: "desc", n: 100 },
      ]
    },
    display_json: {
      columns: %w[securities_code name sector_33_name composite_score growth_score quality_score value_score roe revenue_yoy],
      sort_by: "roe", sort_order: "desc", limit: 100,
    },
  },
].freeze

BUILTIN_PRESETS.each do |preset_data|
  ScreeningPreset.find_or_initialize_by(name: preset_data[:name], preset_type: :builtin).tap do |p|
    p.conditions_json = preset_data[:conditions_json]
    p.display_json = preset_data[:display_json]
    p.description = preset_data[:description]
    p.status = :enabled
    p.save!
  end
end
