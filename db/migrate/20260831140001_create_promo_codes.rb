class CreatePromoCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :promo_codes do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :campaign,  null: true,  foreign_key: true
      t.references :reward,    null: false, foreign_key: true

      t.string   :token,           null: false
      t.integer  :max_claims                          # nil = unlimited
      t.integer  :claims_count,    null: false, default: 0
      t.integer  :scan_count,      null: false, default: 0
      t.integer  :per_member_limit, null: false, default: 1
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean  :active,          null: false, default: true

      t.timestamps
    end

    add_index :promo_codes, [ :workspace_id, :token ], unique: true
  end
end
