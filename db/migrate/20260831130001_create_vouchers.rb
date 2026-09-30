class CreateVouchers < ActiveRecord::Migration[7.2]
  def change
    create_table :vouchers do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.references :reward,    null: false, foreign_key: true

      t.string   :code,   null: false                 # permanent human-readable voucher id
      t.string   :source, null: false, default: "redeem" # redeem/claim_qr/campaign/birthday/referral
      t.string   :state,  null: false, default: "active" # active/used/expired
      t.integer  :points_spent, null: false, default: 0
      t.datetime :expires_at                            # voucher validity window

      # One-time point-of-use redemption code (§6.4)
      t.string   :redeem_token
      t.datetime :redeem_token_expires_at
      t.datetime :used_at
      t.references :used_outlet, null: true, foreign_key: { to_table: :outlets }
      t.references :used_by_staff, null: true, foreign_key: { to_table: :users }

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :vouchers, [ :workspace_id, :code ], unique: true
    add_index :vouchers, [ :workspace_id, :redeem_token ]
    add_index :vouchers, [ :member_id, :state ]
  end
end
