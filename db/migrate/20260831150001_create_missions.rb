class CreateMissions < ActiveRecord::Migration[7.2]
  def change
    create_table :missions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :title,        null: false
      t.string  :icon
      t.string  :mission_type, null: false, default: "checkin" # checkin/spend/visit/refer
      t.string  :period,       null: false, default: "daily"   # daily/weekly
      t.integer :goal,         null: false, default: 1
      t.integer :reward_points, null: false, default: 20
      t.boolean :active,       null: false, default: true
      t.integer :position,     null: false, default: 0
      t.timestamps
    end

    create_table :mission_progresses do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :mission,   null: false, foreign_key: true
      t.string   :period_key, null: false        # e.g. 2026-08-31 (daily) / 2026-W35 (weekly)
      t.integer  :progress,   null: false, default: 0
      t.datetime :completed_at
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :mission_progresses, [ :member_id, :mission_id, :period_key ], unique: true,
              name: "idx_mission_progress_unique"
  end
end
