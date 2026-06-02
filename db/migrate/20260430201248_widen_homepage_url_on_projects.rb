class WidenHomepageUrlOnProjects < ActiveRecord::Migration[8.1]
  def up
    change_column :projects, :homepage_url, :string, limit: 500
  end

  def down
    change_column :projects, :homepage_url, :string, limit: 255
  end
end
