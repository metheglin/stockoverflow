class CreateFinancialValues < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_values do |t|
      t.references :company, null: false, foreign_key: true
      t.references :financial_report, null: true, foreign_key: true
      t.integer :scope, null: false, default: 0
      t.integer :period_type, null: false
      t.date :fiscal_year_end, null: false

      # P/L
      t.bigint :net_sales
      t.bigint :operating_income
      t.bigint :ordinary_income
      t.bigint :net_income
      t.decimal :eps, precision: 15, scale: 2
      t.decimal :diluted_eps, precision: 15, scale: 2

      # B/S
      t.bigint :total_assets
      t.bigint :net_assets
      t.decimal :equity_ratio, precision: 7, scale: 2
      t.decimal :bps, precision: 15, scale: 2

      # C/F
      t.bigint :operating_cf
      t.bigint :investing_cf
      t.bigint :financing_cf
      t.bigint :cash_and_equivalents

      # 株式情報
      t.bigint :shares_outstanding
      t.bigint :treasury_shares

      # 拡張データ
      t.json :data_json

      t.timestamps
    end

    add_index :financial_values, [:company_id, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_fin_values_unique"
    add_index :financial_values, :fiscal_year_end
  end
end
