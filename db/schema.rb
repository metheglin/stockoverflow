# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_27_180740) do
  create_table "application_properties", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data_json", default: "{}", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_application_properties_on_kind", unique: true
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data_json"
    t.string "edinet_code"
    t.boolean "listed", default: true, null: false
    t.string "market_code"
    t.string "market_name"
    t.string "name", null: false
    t.string "name_english"
    t.string "scale_category"
    t.string "sector_17_code"
    t.string "sector_17_name"
    t.string "sector_33_code"
    t.string "sector_33_name"
    t.string "securities_code"
    t.datetime "updated_at", null: false
    t.index ["edinet_code"], name: "index_companies_on_edinet_code", unique: true
    t.index ["listed"], name: "index_companies_on_listed"
    t.index ["securities_code"], name: "index_companies_on_securities_code", unique: true
  end

  create_table "daily_quotes", force: :cascade do |t|
    t.decimal "adjusted_close", precision: 12, scale: 2
    t.decimal "adjustment_factor", precision: 12, scale: 6
    t.decimal "close_price", precision: 12, scale: 2
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.decimal "high_price", precision: 12, scale: 2
    t.decimal "low_price", precision: 12, scale: 2
    t.decimal "open_price", precision: 12, scale: 2
    t.date "traded_on", null: false
    t.bigint "turnover_value"
    t.datetime "updated_at", null: false
    t.bigint "volume"
    t.index ["company_id", "traded_on"], name: "index_daily_quotes_on_company_id_and_traded_on", unique: true
    t.index ["company_id"], name: "index_daily_quotes_on_company_id"
    t.index ["traded_on"], name: "index_daily_quotes_on_traded_on"
  end

  create_table "financial_events", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.integer "event_type", null: false
    t.integer "financial_metric_id", null: false
    t.date "fiscal_year_end", null: false
    t.integer "severity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "event_type", "fiscal_year_end"], name: "idx_fin_events_unique", unique: true
    t.index ["company_id", "fiscal_year_end"], name: "index_financial_events_on_company_id_and_fiscal_year_end"
    t.index ["company_id"], name: "index_financial_events_on_company_id"
    t.index ["event_type", "created_at"], name: "index_financial_events_on_event_type_and_created_at"
    t.index ["financial_metric_id"], name: "index_financial_events_on_financial_metric_id"
  end

  create_table "financial_metrics", force: :cascade do |t|
    t.integer "company_id", null: false
    t.integer "consecutive_profit_growth", default: 0, null: false
    t.integer "consecutive_revenue_growth", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.decimal "eps_yoy", precision: 10, scale: 4
    t.integer "financial_value_id", null: false
    t.date "fiscal_year_end", null: false
    t.bigint "free_cf"
    t.boolean "free_cf_positive"
    t.boolean "investing_cf_negative"
    t.decimal "net_income_yoy", precision: 10, scale: 4
    t.decimal "net_margin", precision: 10, scale: 4
    t.boolean "operating_cf_positive"
    t.decimal "operating_income_yoy", precision: 10, scale: 4
    t.decimal "operating_margin", precision: 10, scale: 4
    t.decimal "ordinary_income_yoy", precision: 10, scale: 4
    t.decimal "ordinary_margin", precision: 10, scale: 4
    t.integer "period_type", null: false
    t.decimal "revenue_yoy", precision: 10, scale: 4
    t.decimal "roa", precision: 10, scale: 4
    t.decimal "roe", precision: 10, scale: 4
    t.integer "scope", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year_end", "scope", "period_type"], name: "idx_fin_metrics_unique", unique: true
    t.index ["company_id", "scope", "period_type", "fiscal_year_end"], name: "idx_financial_metrics_timeline"
    t.index ["company_id"], name: "index_financial_metrics_on_company_id"
    t.index ["consecutive_profit_growth"], name: "index_financial_metrics_on_consecutive_profit_growth"
    t.index ["consecutive_revenue_growth"], name: "index_financial_metrics_on_consecutive_revenue_growth"
    t.index ["financial_value_id"], name: "index_financial_metrics_on_financial_value_id"
    t.index ["fiscal_year_end"], name: "index_financial_metrics_on_fiscal_year_end"
    t.index ["scope", "period_type", "consecutive_profit_growth"], name: "idx_financial_metrics_screening_profit"
    t.index ["scope", "period_type", "consecutive_revenue_growth", "revenue_yoy"], name: "idx_financial_metrics_screening_revenue"
    t.index ["scope", "period_type", "operating_cf_positive", "investing_cf_negative"], name: "idx_financial_metrics_cashflow"
  end

  create_table "financial_reports", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.date "disclosed_at"
    t.string "doc_id"
    t.string "doc_type_code"
    t.date "fiscal_year_end"
    t.date "fiscal_year_start"
    t.date "period_end"
    t.date "period_start"
    t.integer "report_type", null: false
    t.integer "source", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year_end", "report_type"], name: "idx_fin_reports_company_year_type"
    t.index ["company_id"], name: "index_financial_reports_on_company_id"
    t.index ["disclosed_at"], name: "index_financial_reports_on_disclosed_at"
    t.index ["doc_id"], name: "index_financial_reports_on_doc_id", unique: true
    t.index ["fiscal_year_end"], name: "index_financial_reports_on_fiscal_year_end"
  end

  create_table "financial_values", force: :cascade do |t|
    t.decimal "bps", precision: 15, scale: 2
    t.bigint "cash_and_equivalents"
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.decimal "diluted_eps", precision: 15, scale: 2
    t.decimal "eps", precision: 15, scale: 2
    t.decimal "equity_ratio", precision: 7, scale: 2
    t.integer "financial_report_id"
    t.bigint "financing_cf"
    t.date "fiscal_year_end", null: false
    t.bigint "investing_cf"
    t.bigint "net_assets"
    t.bigint "net_income"
    t.bigint "net_sales"
    t.bigint "operating_cf"
    t.bigint "operating_income"
    t.bigint "ordinary_income"
    t.integer "period_type", null: false
    t.integer "scope", default: 0, null: false
    t.bigint "shares_outstanding"
    t.bigint "total_assets"
    t.bigint "treasury_shares"
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year_end", "scope", "period_type"], name: "idx_fin_values_unique", unique: true
    t.index ["company_id", "scope", "period_type", "fiscal_year_end"], name: "idx_financial_values_timeline"
    t.index ["company_id"], name: "index_financial_values_on_company_id"
    t.index ["financial_report_id"], name: "index_financial_values_on_financial_report_id"
    t.index ["fiscal_year_end"], name: "index_financial_values_on_fiscal_year_end"
  end

  create_table "screening_presets", force: :cascade do |t|
    t.json "conditions_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.json "display_json", default: {}, null: false
    t.integer "execution_count", default: 0, null: false
    t.datetime "last_executed_at"
    t.string "name", null: false
    t.integer "preset_type", default: 0, null: false
    t.integer "status", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["preset_type"], name: "index_screening_presets_on_preset_type"
    t.index ["status"], name: "index_screening_presets_on_status"
  end

  create_table "sector_metrics", force: :cascade do |t|
    t.date "calculated_on", null: false
    t.integer "classification", null: false
    t.integer "company_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.string "sector_code", null: false
    t.string "sector_name", null: false
    t.datetime "updated_at", null: false
    t.index ["classification", "calculated_on"], name: "idx_sector_metrics_classification_date"
    t.index ["classification", "sector_code", "calculated_on"], name: "idx_sector_metrics_unique", unique: true
  end

  create_table "trend_turning_points", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.json "data_json"
    t.integer "financial_metric_id", null: false
    t.date "fiscal_year_end", null: false
    t.integer "pattern_type", null: false
    t.integer "period_type", null: false
    t.integer "scope", default: 0, null: false
    t.integer "significance", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year_end"], name: "idx_ttp_company_fy"
    t.index ["company_id", "pattern_type", "fiscal_year_end", "scope", "period_type"], name: "idx_ttp_unique", unique: true
    t.index ["company_id"], name: "index_trend_turning_points_on_company_id"
    t.index ["financial_metric_id"], name: "index_trend_turning_points_on_financial_metric_id"
    t.index ["pattern_type", "fiscal_year_end"], name: "idx_ttp_pattern_fy"
  end

  add_foreign_key "daily_quotes", "companies"
  add_foreign_key "financial_events", "companies"
  add_foreign_key "financial_events", "financial_metrics"
  add_foreign_key "financial_metrics", "companies"
  add_foreign_key "financial_metrics", "financial_values"
  add_foreign_key "financial_reports", "companies"
  add_foreign_key "financial_values", "companies"
  add_foreign_key "financial_values", "financial_reports"
  add_foreign_key "trend_turning_points", "companies"
  add_foreign_key "trend_turning_points", "financial_metrics"
end
