class CreateMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :members do |t|
      t.references :workspace, null: false, foreign_key: true

      ## Identity (phone-first; email optional)
      t.string :phone,  null: false
      t.string :email
      t.string :name,   null: false, default: ""
      t.date   :birthday
      t.string :locale, null: false, default: "vi"
      t.string :gender

      ## Loyalty caches (source of truth = point_transactions ledger)
      t.integer :points_balance,  null: false, default: 0
      t.integer :lifetime_points, null: false, default: 0
      t.string  :tier_key
      t.references :referred_by, null: true, foreign_key: { to_table: :members }
      t.string :referral_code

      ## Devise (database_authenticatable kept for Warden session; login is phone+OTP)
      t.string   :encrypted_password, null: false, default: ""
      t.datetime :remember_created_at
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :members, [ :workspace_id, :phone ], unique: true
    add_index :members, [ :workspace_id, :referral_code ], unique: true, where: "referral_code IS NOT NULL"
    add_index :members, [ :workspace_id, :tier_key ]
  end
end
