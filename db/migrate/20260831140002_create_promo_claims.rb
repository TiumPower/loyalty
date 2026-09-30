class CreatePromoClaims < ActiveRecord::Migration[7.2]
  def change
    create_table :promo_claims do |t|
      t.references :workspace,  null: false, foreign_key: true
      t.references :promo_code, null: false, foreign_key: true
      t.references :member,     null: false, foreign_key: true
      t.references :voucher,    null: true,  foreign_key: true

      t.timestamps
    end

    add_index :promo_claims, [ :promo_code_id, :member_id ], unique: true
  end
end
