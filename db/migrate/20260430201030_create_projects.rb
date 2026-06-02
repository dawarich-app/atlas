class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :user,         null: false, foreign_key: true
      t.string     :slug,         null: false
      t.string     :name,         null: false
      t.text       :description
      t.string     :homepage_url
      t.timestamps
    end
    add_index :projects, "lower(slug)", unique: true, name: "index_projects_on_lower_slug"
  end
end
