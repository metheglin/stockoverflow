class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :edinet_code, null: true
      t.string :securities_code, null: true
      t.string :name, null: false
      t.string :name_english
      t.string :sector_17_code
      t.string :sector_17_name
      t.string :sector_33_code
      t.string :sector_33_name
      t.string :market_code
      t.string :market_name
      t.string :scale_category
      t.boolean :listed, null: false, default: true
      t.json :data_json
      t.timestamps
    end

    add_index :companies, :edinet_code, unique: true
    add_index :companies, :securities_code, unique: true
    add_index :companies, :listed
  end
end
