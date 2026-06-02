class CreateVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :versions do |t|
      t.references :project,    null: false, foreign_key: true
      t.string     :number,     null: false
      t.date       :released_at
      t.boolean    :yanked,     null: false, default: false
      t.timestamps
    end
    add_index :versions, [:project_id, :number], unique: true
    add_index :versions, [:project_id, :released_at]
  end
end
