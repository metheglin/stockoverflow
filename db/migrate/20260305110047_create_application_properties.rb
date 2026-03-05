class CreateApplicationProperties < ActiveRecord::Migration[8.1]
  def change
    create_table :application_properties do |t|
      t.integer :kind, null: false, default: 0
      t.json :data_json, null: false, default: {}
      t.timestamps
    end

    add_index :application_properties, :kind, unique: true
  end
end
