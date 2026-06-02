class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries do |t|
      t.references :version,       null: false, foreign_key: true
      t.string     :kind,          null: false
      t.text       :body_markdown, null: false
      t.jsonb      :body_tokens,   null: false, default: []
      t.integer    :position,      null: false, default: 0
      t.timestamps
    end
    add_index :entries, [:version_id, :position]
  end
end
