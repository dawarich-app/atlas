class AddPartialUniqueIndexOnVersionsUnreleased < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :versions, :project_id,
              unique: true,
              where: "released_at IS NULL",
              name: "index_versions_on_project_id_unreleased",
              algorithm: :concurrently
  end
end
