Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  resources :vineyards do
    member do
      get :rows
      get :stats
    end
    collection do
      get :total_stats
      get :select_stats
      post :select_stats
    end
  end

  resources :rows do
    member do
      get :bushes  # GET /rows/:id/bushes.json
    end
  end

  resources :folders do
    member do
      get :attach
      get :edit_attach
      post :attach_to_vineyard
      patch :update_attach_to_vineyard  # перекрепление ЭТОГО медиа к кусту
      delete :detach_from_vineyard
    end
    collection do
      get :select_page
      post :select_page
    end
  end

  resources :media_items do
    member do
      get :attach              # страница выбора куста для ЭТОГО медиа
      get :edit_attach
      post :classify  # классификация одного изображения
      post :attach_to_bush     # прикрепление ЭТОГО медиа к кусту
      patch :update_attach_to_bush  # перекрепление ЭТОГО медиа к кусту
      delete :detach_from_bush
    end
  end

  namespace :active_storage do
    resources :blobs, only: [ :destroy ]
  end

  post "/rails/active_storage/direct_uploads", to: "active_storage/direct_uploads#create"

  root "vineyards#index"

  get "*unmatched", to: "application#not_found", via: :all, constraints: ->(req) {
    # Исключаем Active Storage и ассеты
    !req.path.start_with?("/rails/active_storage/") &&
    !req.path.start_with?("/assets/")
  }
end
