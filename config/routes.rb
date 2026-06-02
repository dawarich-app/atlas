Rails.application.routes.draw do
  if Rails.env.test?
    get "/spec/host/:fixture", to: ->(env) {
      name = env["action_dispatch.request.path_parameters"][:fixture].to_s
      safe = name.match?(/\A[a-z0-9_]+\z/) ? name : "default"
      body = File.read(Rails.root.join("spec/fixtures/widget_host_page/host_#{safe}.html"))
      [200, { "Content-Type" => "text/html" }, [body]]
    }
    get "/spec/host", to: redirect("/spec/host/default")
  end

  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  root to: "home#index"

  namespace :authors do
    resources :projects, param: :slug do
      resources :versions, only: [] do
        member do
          patch :release
          patch :yank
        end
      end
      resources :entries, only: %i[create update destroy]
    end
  end

  scope module: :public, path: "c" do
    get ":slug",       to: "changelogs#show", as: :public_changelog
    get ":slug.json",  to: "changelogs#show", defaults: { format: :json }
    get ":slug.rss",   to: "changelogs#show", defaults: { format: :rss }
  end

  scope module: :widget, path: "w/v1" do
    get "loader.js",     to: "assets#loader",  as: :widget_loader
    get ":slug.json",    to: "loaders#show",   as: :widget_payload
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
