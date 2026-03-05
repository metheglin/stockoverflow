class CreateDailyQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_quotes do |t|
      t.references :company, null: false, foreign_key: true
      t.date :traded_on, null: false
      t.decimal :open_price, precision: 12, scale: 2
      t.decimal :high_price, precision: 12, scale: 2
      t.decimal :low_price, precision: 12, scale: 2
      t.decimal :close_price, precision: 12, scale: 2
      t.bigint :volume
      t.bigint :turnover_value
      t.decimal :adjustment_factor, precision: 12, scale: 6
      t.decimal :adjusted_close, precision: 12, scale: 2
      t.json :data_json
      t.timestamps
    end

    add_index :daily_quotes, [:company_id, :traded_on], unique: true
    add_index :daily_quotes, :traded_on
  end
end
