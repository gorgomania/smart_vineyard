Rails.application.routes.draw do
  resources :folders
  resources :media_items do
    member do
      post :classify  # классификация одного изображения
    end
  end
  resources :maps
  resources :stats

  root "maps#index"
end
