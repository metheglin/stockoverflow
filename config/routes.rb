Rails.application.routes.draw do
  root "dashboard#index"

  namespace :dashboard do
    root "search#index"

    # Search dashboard
    resources :search, only: [:index] do
      collection do
        post :execute
      end
    end

    # Search presets
    resources :presets, only: [:index, :create, :show, :destroy]

    # Company dashboard
    resources :companies, only: [:index, :show] do
      member do
        get :financials
        get :metrics
        get :quotes
        get :compare
        get :chart_data
      end
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
