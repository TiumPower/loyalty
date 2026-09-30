class CreateBadges < ActiveRecord::Migration[7.2]
  def change
    create_table :badges do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :key,          null: false
      t.string  :name,         null: false
      t.text    :description
      t.string  :icon
      t.string  :criteria_type, null: false, default: "purchases_count" # first_purchase/purchases_count/points_total/night_owl
      t.integer :threshold,    null: false, default: 1
      t.integer :position,     null: false, default: 0
      t.timestamps
    end
    add_index :badges, [ :workspace_id, :key ], unique: true

    create_table :member_badges do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :badge,     null: false, foreign_key: true
      t.datetime :earned_at,   null: false
      t.timestamps
    end
    add_index :member_badges, [ :member_id, :badge_id ], unique: true
  end
end
