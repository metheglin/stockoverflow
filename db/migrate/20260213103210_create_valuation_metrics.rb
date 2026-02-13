class CreateValuationMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :valuation_metrics do |t|
      t.references :company, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :per, precision: 10, scale: 4
      t.decimal :pbr, precision: 10, scale: 4
      t.decimal :psr, precision: 10, scale: 4
      t.decimal :pcfr, precision: 10, scale: 4
      t.decimal :dividend_yield, precision: 10, scale: 4
      t.decimal :market_cap, precision: 20, scale: 2

      t.timestamps
    end

    add_index :valuation_metrics, [:company_id, :date], unique: true
  end
end
