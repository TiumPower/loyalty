class CreatePointTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :point_transactions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :outlet,    null: true,  foreign_key: true
      t.references :staff,     null: true,  foreign_key: { to_table: :users }
      t.references :source,    polymorphic: true, null: true

      t.string   :kind,   null: false, default: "earn" # earn/redeem/adjust/expire/referral/mission/game/birthday
      t.integer  :amount, null: false, default: 0       # signed: + earn, - redeem/expire
      t.string   :note
      t.datetime :expires_at
      t.jsonb    :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :point_transactions, [ :workspace_id, :member_id, :created_at ]
    add_index :point_transactions, [ :member_id, :kind ]
  end
end
