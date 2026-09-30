class CreatePosCharges < ActiveRecord::Migration[7.2]
  def change
    create_table :pos_charges do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :outlet,    null: true,  foreign_key: true
      t.references :staff,     null: true,  foreign_key: { to_table: :users }
      t.references :member,    null: true,  foreign_key: true
      t.references :purchase,  null: true,  foreign_key: true

      t.string   :token,   null: false
      t.integer  :amount,  null: false, default: 0
      t.string   :state,   null: false, default: "open" # open / claimed / expired
      t.integer  :points_awarded, null: false, default: 0
      t.datetime :expires_at
      t.datetime :claimed_at

      t.timestamps
    end

    add_index :pos_charges, [ :workspace_id, :token ], unique: true
  end
end
