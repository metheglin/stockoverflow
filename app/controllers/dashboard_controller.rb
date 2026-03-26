class DashboardController < ApplicationController
  layout "dashboard"

  def index
    redirect_to dashboard_root_path
  end
end
