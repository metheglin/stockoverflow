class CreateStockPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_prices do |t|
      t.references :company, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :open_price, precision: 15, scale: 2
      t.decimal :high_price, precision: 15, scale: 2
      t.decimal :low_price, precision: 15, scale: 2
      t.decimal :close_price, precision: 15, scale: 2
      t.integer :volume, limit: 8
      t.decimal :adjusted_close, precision: 15, scale: 2

      t.timestamps
    end

    add_index :stock_prices, [:company_id, :date], unique: true
    add_index :stock_prices, :date
  end
end
