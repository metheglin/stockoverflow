class CreateProfitabilityMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :profitability_metrics do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :fiscal_period, null: false
      t.decimal :roe, precision: 10, scale: 4
      t.decimal :roa, precision: 10, scale: 4
      t.decimal :operating_margin, precision: 10, scale: 4
      t.decimal :net_margin, precision: 10, scale: 4
      t.decimal :gross_margin, precision: 10, scale: 4

      t.timestamps
    end

    add_index :profitability_metrics, [:company_id, :fiscal_year, :fiscal_period],
              unique: true, name: 'index_pm_on_company_year_period'
  end
end
