class CreateFinancialEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_events do |t|
      t.references :company, null: false, foreign_key: true
      t.references :financial_metric, null: false, foreign_key: true
      t.integer :event_type, null: false
      t.integer :severity, null: false, default: 0
      t.date :fiscal_year_end, null: false
      t.json :data_json
      t.timestamps
    end

    add_index :financial_events, [:company_id, :fiscal_year_end]
    add_index :financial_events, [:event_type, :created_at]
    add_index :financial_events, [:company_id, :event_type, :fiscal_year_end], unique: true, name: "idx_fin_events_unique"
  end
end
