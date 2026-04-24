Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  resources :folders
  resources :vineyards
  resources :users
  resources :stats
  resources :media_items do
    member do
      post :classify  # классификация одного изображения
    end
  end
  root "vineyards#index"
  get '*unmatched', to: 'application#not_found', via: :all, constraints: ->(req) {
    # Исключаем Active Storage и ассеты
    !req.path.start_with?('/rails/active_storage/') &&
    !req.path.start_with?('/assets/')
  }
end
