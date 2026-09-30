class CreatePurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :purchases do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :outlet,    null: true,  foreign_key: true
      t.references :staff,     null: true,  foreign_key: { to_table: :users }

      t.integer :amount,        null: false, default: 0 # bill amount in currency units
      t.integer :points_earned, null: false, default: 0
      t.string  :source,        null: false, default: "staff_scan" # staff_scan/pos_scan/manual
      t.jsonb   :metadata,      null: false, default: {}

      t.timestamps
    end

    add_index :purchases, [ :workspace_id, :created_at ]
  end
end
