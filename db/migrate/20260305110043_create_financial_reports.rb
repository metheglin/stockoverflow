class CreateFinancialReports < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_reports do |t|
      t.references :company, null: false, foreign_key: true
      t.string :doc_id
      t.string :doc_type_code
      t.integer :report_type, null: false
      t.date :fiscal_year_start
      t.date :fiscal_year_end
      t.date :period_start
      t.date :period_end
      t.datetime :submitted_at
      t.date :disclosed_at
      t.integer :source, null: false
      t.json :data_json
      t.timestamps
    end

    add_index :financial_reports, :doc_id, unique: true
    add_index :financial_reports, [:company_id, :fiscal_year_end, :report_type], name: "idx_fin_reports_company_year_type"
    add_index :financial_reports, :fiscal_year_end
    add_index :financial_reports, :disclosed_at
  end
end
