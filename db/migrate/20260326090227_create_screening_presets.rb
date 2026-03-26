class CreateScreeningPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :screening_presets do |t|
      t.string :name, null: false
      t.text :description
      t.integer :preset_type, null: false, default: 0
      t.json :conditions_json, null: false, default: {}
      t.json :display_json, null: false, default: {}
      t.integer :status, null: false, default: 1
      t.integer :execution_count, null: false, default: 0
      t.datetime :last_executed_at

      t.timestamps
    end

    add_index :screening_presets, :preset_type
    add_index :screening_presets, :status
  end
end
