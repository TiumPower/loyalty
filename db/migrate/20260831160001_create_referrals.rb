class CreateReferrals < ActiveRecord::Migration[7.2]
  def change
    create_table :referrals do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :referrer, null: false, foreign_key: { to_table: :members }
      t.references :referred, null: false, foreign_key: { to_table: :members },
                   index: { unique: true }
      t.string   :state, null: false, default: "pending" # pending / completed
      t.integer  :reward_points, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    add_index :referrals, [ :workspace_id, :referrer_id ]
  end
end
