class CreateTrendTurningPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :trend_turning_points do |t|
      t.references :company, null: false, foreign_key: true
      t.references :financial_metric, null: false, foreign_key: true
      t.date :fiscal_year_end, null: false
      t.integer :scope, default: 0, null: false
      t.integer :period_type, null: false
      t.integer :pattern_type, null: false
      t.integer :significance, default: 1, null: false
      t.json :data_json
      t.timestamps
    end

    add_index :trend_turning_points, [:company_id, :fiscal_year_end], name: "idx_ttp_company_fy"
    add_index :trend_turning_points, [:pattern_type, :fiscal_year_end], name: "idx_ttp_pattern_fy"
    add_index :trend_turning_points, [:company_id, :pattern_type, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_ttp_unique"
  end
end
