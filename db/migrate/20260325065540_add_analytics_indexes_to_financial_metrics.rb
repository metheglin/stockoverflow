class AddAnalyticsIndexesToFinancialMetrics < ActiveRecord::Migration[8.1]
  def change
    # Timeline: company_id + scope + period_type + fiscal_year_end order
    # Existing unique index (company_id, fiscal_year_end, scope, period_type) has
    # fiscal_year_end before scope/period_type, which is suboptimal for queries that
    # filter by scope/period_type and sort by fiscal_year_end.
    add_index :financial_metrics,
      [:company_id, :scope, :period_type, :fiscal_year_end],
      name: "idx_financial_metrics_timeline"

    # Screening: scope + period_type + consecutive_revenue_growth for filtering,
    # revenue_yoy for sorting
    add_index :financial_metrics,
      [:scope, :period_type, :consecutive_revenue_growth, :revenue_yoy],
      name: "idx_financial_metrics_screening_revenue"

    # Screening: scope + period_type + consecutive_profit_growth for profit-based screening
    add_index :financial_metrics,
      [:scope, :period_type, :consecutive_profit_growth],
      name: "idx_financial_metrics_screening_profit"

    # Cash flow screening: operating_cf_positive + investing_cf_negative filtering
    add_index :financial_metrics,
      [:scope, :period_type, :operating_cf_positive, :investing_cf_negative],
      name: "idx_financial_metrics_cashflow"

    # Timeline for financial_values: same pattern as metrics
    add_index :financial_values,
      [:company_id, :scope, :period_type, :fiscal_year_end],
      name: "idx_financial_values_timeline"
  end
end
