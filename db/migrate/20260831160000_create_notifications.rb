class CreateNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :broadcasts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.string   :segment_key, null: false, default: "all"
      t.string   :title,   null: false
      t.text     :body
      t.integer  :sent_count, null: false, default: 0
      t.datetime :sent_at
      t.timestamps
    end

    create_table :notifications do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :broadcast, null: true,  foreign_key: true
      t.string   :title, null: false
      t.text     :body
      t.string   :kind,  null: false, default: "promo" # promo/reminder/system/reward
      t.string   :icon
      t.string   :deep_link
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :member_id, :read_at ]
    add_index :notifications, [ :member_id, :created_at ]
  end
end
