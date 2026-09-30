class CreateOtpChallenges < ActiveRecord::Migration[7.2]
  def change
    create_table :otp_challenges do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string   :phone,   null: false
      t.string   :code,    null: false
      t.string   :purpose, null: false, default: "login"
      t.integer  :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :otp_challenges, [ :workspace_id, :phone, :purpose ]
  end
end
