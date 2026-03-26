Rails.application.routes.draw do
  resources :folders
  resources :media_items do
    member do
      post :classify  # классификация одного изображения
    end
  end
  resources :maps
  resources :stats

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "maps#index"
end
