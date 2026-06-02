class CreateBeaconEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :beacon_events do |t|
      t.references :project, null: false, foreign_key: true
      t.string     :origin,  null: false, limit: 200
      t.string     :version, null: false, limit: 100
      t.datetime   :created_at, null: false
    end
    add_index :beacon_events, [:project_id, :origin, :created_at]
    add_index :beacon_events, :created_at
  end
end
