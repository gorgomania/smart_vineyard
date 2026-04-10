Rails.application.routes.draw do
  devise_for :users
  resources :folders
  resources :maps
  resources :users
  resources :stats
  resources :media_items do
    member do
      post :classify  # классификация одного изображения
    end
  end
  match "*unmatched", to: "application#error_not_found", via: :all
  root "maps#index"
end
