Rails.application.routes.draw do
  resources :dns do
    scope module: 'dns' do
      resources :collaborators,
                :records
    end
  end
end
