class Dashboard::PresetsController < Dashboard::BaseController
  def index
    @presets = ScreeningPreset.enabled.order(updated_at: :desc)
  end

  def show
    @preset = ScreeningPreset.find(params[:id])
    executor = ScreeningPreset::ConditionExecutor.new(
      conditions_json: @preset.conditions_json,
      display_json: @preset.display_json
    )
    @results = executor.execute
    @preset.record_execution!
  end

  def create
    @preset = ScreeningPreset.new(preset_params)
    @preset.preset_type = :custom
    if @preset.save
      redirect_to dashboard_preset_path(@preset)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @preset = ScreeningPreset.find(params[:id])
    @preset.destroy if @preset.custom?
    redirect_to dashboard_presets_path
  end

  private

  def preset_params
    params.require(:screening_preset).permit(:name, :description, :conditions_json, :display_json)
  end
end
