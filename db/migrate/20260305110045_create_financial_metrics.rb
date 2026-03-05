class CreateFinancialMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_metrics do |t|
      t.references :company, null: false, foreign_key: true
      t.references :financial_value, null: false, foreign_key: true
      t.integer :scope, null: false, default: 0
      t.integer :period_type, null: false
      t.date :fiscal_year_end, null: false

      # 成長性指標 (YoY)
      t.decimal :revenue_yoy, precision: 10, scale: 4
      t.decimal :operating_income_yoy, precision: 10, scale: 4
      t.decimal :ordinary_income_yoy, precision: 10, scale: 4
      t.decimal :net_income_yoy, precision: 10, scale: 4
      t.decimal :eps_yoy, precision: 10, scale: 4

      # 収益性指標
      t.decimal :roe, precision: 10, scale: 4
      t.decimal :roa, precision: 10, scale: 4
      t.decimal :operating_margin, precision: 10, scale: 4
      t.decimal :ordinary_margin, precision: 10, scale: 4
      t.decimal :net_margin, precision: 10, scale: 4

      # CF指標
      t.bigint :free_cf
      t.boolean :operating_cf_positive
      t.boolean :investing_cf_negative
      t.boolean :free_cf_positive

      # 連続指標
      t.integer :consecutive_revenue_growth, null: false, default: 0
      t.integer :consecutive_profit_growth, null: false, default: 0

      # 拡張指標
      t.json :data_json

      t.timestamps
    end

    add_index :financial_metrics, [:company_id, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_fin_metrics_unique"
    add_index :financial_metrics, :fiscal_year_end
    add_index :financial_metrics, :consecutive_revenue_growth
    add_index :financial_metrics, :consecutive_profit_growth
  end
end
