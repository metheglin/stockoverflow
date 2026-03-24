class CreateSectorMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :sector_metrics do |t|
      t.integer :classification, null: false
      t.string :sector_code, null: false
      t.string :sector_name, null: false
      t.date :calculated_on, null: false
      t.integer :company_count, default: 0, null: false
      t.json :data_json

      t.timestamps
    end

    add_index :sector_metrics,
              [:classification, :sector_code, :calculated_on],
              unique: true,
              name: "idx_sector_metrics_unique"
    add_index :sector_metrics,
              [:classification, :calculated_on],
              name: "idx_sector_metrics_classification_date"
  end
end
