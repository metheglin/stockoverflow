class Dashboard::SearchController < Dashboard::BaseController
  def index
    @presets = ScreeningPreset.enabled.order(execution_count: :desc)
  end

  # POST /dashboard/search/execute
  def execute
    conditions_json = parse_conditions_params
    display_json = parse_display_params

    executor = ScreeningPreset::ConditionExecutor.new(
      conditions_json: conditions_json,
      display_json: display_json
    )
    @results = executor.execute
    @display_columns = display_json[:columns] || default_display_columns

    respond_to do |format|
      format.turbo_stream
      format.json { render json: serialize_results(@results) }
    end
  end

  private

  def parse_conditions_params
    return JSON.parse(params[:conditions_json]) if params[:conditions_json].is_a?(String)
    return params[:conditions_json].to_unsafe_h if params[:conditions_json].respond_to?(:to_unsafe_h)
    {}
  end

  def parse_display_params
    raw = if params[:display_json].is_a?(String)
            JSON.parse(params[:display_json])
          elsif params[:display_json].respond_to?(:to_unsafe_h)
            params[:display_json].to_unsafe_h
          else
            {}
          end
    raw.deep_symbolize_keys
  end

  def default_display_columns
    %w[securities_code name sector_33_name revenue_yoy operating_income_yoy roe composite_score]
  end

  def serialize_results(results)
    results.map do |result|
      company = result[:company]
      metric = result[:metric]
      {
        securities_code: company.securities_code,
        name: company.name,
        sector_33_name: company.sector_33_name,
        revenue_yoy: metric.revenue_yoy&.to_f,
        operating_income_yoy: metric.operating_income_yoy&.to_f,
        roe: metric.roe&.to_f,
        roa: metric.roa&.to_f,
        operating_margin: metric.operating_margin&.to_f,
        consecutive_revenue_growth: metric.consecutive_revenue_growth,
        consecutive_profit_growth: metric.consecutive_profit_growth,
        composite_score: metric.composite_score&.to_f,
      }
    end
  end
end
