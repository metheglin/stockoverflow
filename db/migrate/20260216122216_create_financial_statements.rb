class CreateFinancialStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_statements do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :fiscal_period, null: false
      t.string :report_type
      t.decimal :net_sales, precision: 20, scale: 2
      t.decimal :operating_income, precision: 20, scale: 2
      t.decimal :ordinary_income, precision: 20, scale: 2
      t.decimal :net_income, precision: 20, scale: 2
      t.decimal :total_assets, precision: 20, scale: 2
      t.decimal :total_equity, precision: 20, scale: 2
      t.decimal :operating_cash_flow, precision: 20, scale: 2
      t.decimal :investing_cash_flow, precision: 20, scale: 2
      t.decimal :financing_cash_flow, precision: 20, scale: 2
      t.bigint :shares_outstanding
      t.date :filed_date

      t.timestamps
    end

    add_index :financial_statements, [:company_id, :fiscal_year, :fiscal_period], unique: true, name: "idx_fin_stmt_company_year_period"
  end
end
