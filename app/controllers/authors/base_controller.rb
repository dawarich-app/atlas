class Authors::BaseController < ApplicationController
  # Dashboard relies on Hotwire/Turbo + modern CSS — scope the modern-browser
  # gate here rather than at ApplicationController, so widget and public pages
  # stay servable to any browser.
  allow_browser versions: :modern

  before_action :authenticate_user!

  layout "application"

  private

  def author_projects
    current_user.projects
  end
end
