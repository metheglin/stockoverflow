class Dashboard::CompaniesController < Dashboard::BaseController
  def index
    @companies = Company.listed.order(:securities_code)
    if params[:q].present?
      q = "%#{params[:q]}%"
      @companies = @companies.where(
        "name LIKE ? OR securities_code LIKE ? OR name_english LIKE ?", q, q, q
      )
    end
    @companies = @companies.limit(100)
  end

  def show
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(
      company: @company,
      scope_type: scope_type_param,
      period_type: period_type_param
    )
  end

  # Turbo Frameで財務データタブを返す
  def financials
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/financials"
  end

  # Turbo Frameで指標タブを返す
  def metrics
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/metrics"
  end

  # Turbo Frameで株価タブを返す
  def quotes
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    render partial: "dashboard/companies/quotes"
  end

  # 比較ビュー（複数指標の並列表示）
  def compare
    @company = Company.find(params[:id])
    @summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    @chart_types = (params[:charts] || "revenue_profit,growth_rates,profitability").split(",").map(&:to_sym)
  end

  # JSON API: グラフデータを返す
  def chart_data
    @company = Company.find(params[:id])
    summary = Company::DashboardSummary.new(company: @company, scope_type: scope_type_param, period_type: period_type_param)
    chart_type = params[:chart_type]&.to_sym || :revenue_profit

    render json: summary.get_chart_data(chart_type)
  end

  private

  def scope_type_param
    params[:scope_type]&.to_sym || :consolidated
  end

  def period_type_param
    params[:period_type]&.to_sym || :annual
  end
end
