class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :market
      t.string :industry
      t.string :sector
      t.date :listing_date

      t.timestamps
    end

    add_index :companies, :code, unique: true
    add_index :companies, :market
    add_index :companies, :industry
    add_index :companies, :sector
  end
end
