class CreateCashFlowMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_flow_metrics do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.string :fiscal_period, null: false
      t.decimal :ocf_to_sales, precision: 10, scale: 4
      t.decimal :free_cash_flow, precision: 20, scale: 2
      t.decimal :cash_conversion_cycle, precision: 10, scale: 2
      t.decimal :ocf_icf_gap, precision: 20, scale: 2

      t.timestamps
    end

    add_index :cash_flow_metrics, [:company_id, :fiscal_year, :fiscal_period],
              unique: true, name: 'index_cfm_on_company_year_period'
  end
end
