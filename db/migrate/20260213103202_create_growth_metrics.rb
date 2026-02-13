class CreateGrowthMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :growth_metrics do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :fiscal_period, null: false
      t.decimal :revenue_growth_rate, precision: 10, scale: 4
      t.decimal :operating_income_growth_rate, precision: 10, scale: 4
      t.decimal :net_income_growth_rate, precision: 10, scale: 4
      t.decimal :eps_growth_rate, precision: 10, scale: 4
      t.decimal :total_assets_growth_rate, precision: 10, scale: 4

      t.timestamps
    end

    add_index :growth_metrics, [:company_id, :fiscal_year, :fiscal_period],
              unique: true, name: 'index_gm_on_company_year_period'
  end
end
