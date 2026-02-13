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

ActiveRecord::Schema[8.1].define(version: 2026_02_13_103216) do
  create_table "cash_flow_metrics", force: :cascade do |t|
    t.decimal "cash_conversion_cycle", precision: 10, scale: 2
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.string "fiscal_period", null: false
    t.integer "fiscal_year", null: false
    t.decimal "free_cash_flow", precision: 20, scale: 2
    t.decimal "ocf_icf_gap", precision: 20, scale: 2
    t.decimal "ocf_to_sales", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year", "fiscal_period"], name: "index_cfm_on_company_year_period", unique: true
    t.index ["company_id"], name: "index_cash_flow_metrics_on_company_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "industry"
    t.date "listing_date"
    t.string "market"
    t.string "name", null: false
    t.string "sector"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_companies_on_code", unique: true
    t.index ["industry"], name: "index_companies_on_industry"
    t.index ["market"], name: "index_companies_on_market"
  end

  create_table "financial_statements", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.date "filed_date"
    t.decimal "financing_cash_flow", precision: 20, scale: 2
    t.string "fiscal_period", null: false
    t.integer "fiscal_year", null: false
    t.decimal "investing_cash_flow", precision: 20, scale: 2
    t.decimal "net_income", precision: 20, scale: 2
    t.decimal "net_sales", precision: 20, scale: 2
    t.decimal "operating_cash_flow", precision: 20, scale: 2
    t.decimal "operating_income", precision: 20, scale: 2
    t.decimal "ordinary_income", precision: 20, scale: 2
    t.string "report_type"
    t.decimal "shares_outstanding", precision: 20, scale: 2
    t.decimal "total_assets", precision: 20, scale: 2
    t.decimal "total_equity", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year", "fiscal_period"], name: "index_fs_on_company_year_period", unique: true
    t.index ["company_id"], name: "index_financial_statements_on_company_id"
    t.index ["filed_date"], name: "index_financial_statements_on_filed_date"
    t.index ["fiscal_year"], name: "index_financial_statements_on_fiscal_year"
  end

  create_table "growth_metrics", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.decimal "eps_growth_rate", precision: 10, scale: 4
    t.string "fiscal_period", null: false
    t.integer "fiscal_year", null: false
    t.decimal "net_income_growth_rate", precision: 10, scale: 4
    t.decimal "operating_income_growth_rate", precision: 10, scale: 4
    t.decimal "revenue_growth_rate", precision: 10, scale: 4
    t.decimal "total_assets_growth_rate", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year", "fiscal_period"], name: "index_gm_on_company_year_period", unique: true
    t.index ["company_id"], name: "index_growth_metrics_on_company_id"
  end

  create_table "profitability_metrics", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.string "fiscal_period", null: false
    t.integer "fiscal_year", null: false
    t.decimal "gross_margin", precision: 10, scale: 4
    t.decimal "net_margin", precision: 10, scale: 4
    t.decimal "operating_margin", precision: 10, scale: 4
    t.decimal "roa", precision: 10, scale: 4
    t.decimal "roe", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year", "fiscal_period"], name: "index_pm_on_company_year_period", unique: true
    t.index ["company_id"], name: "index_profitability_metrics_on_company_id"
  end

  create_table "stock_prices", force: :cascade do |t|
    t.decimal "adjusted_close", precision: 15, scale: 2
    t.decimal "close_price", precision: 15, scale: 2
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.decimal "high_price", precision: 15, scale: 2
    t.decimal "low_price", precision: 15, scale: 2
    t.decimal "open_price", precision: 15, scale: 2
    t.datetime "updated_at", null: false
    t.integer "volume", limit: 8
    t.index ["company_id", "date"], name: "index_stock_prices_on_company_id_and_date", unique: true
    t.index ["company_id"], name: "index_stock_prices_on_company_id"
    t.index ["date"], name: "index_stock_prices_on_date"
  end

  create_table "valuation_metrics", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.decimal "dividend_yield", precision: 10, scale: 4
    t.decimal "market_cap", precision: 20, scale: 2
    t.decimal "pbr", precision: 10, scale: 4
    t.decimal "pcfr", precision: 10, scale: 4
    t.decimal "per", precision: 10, scale: 4
    t.decimal "psr", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.index ["company_id", "date"], name: "index_valuation_metrics_on_company_id_and_date", unique: true
    t.index ["company_id"], name: "index_valuation_metrics_on_company_id"
  end

  add_foreign_key "cash_flow_metrics", "companies"
  add_foreign_key "financial_statements", "companies"
  add_foreign_key "growth_metrics", "companies"
  add_foreign_key "profitability_metrics", "companies"
  add_foreign_key "stock_prices", "companies"
  add_foreign_key "valuation_metrics", "companies"
end
