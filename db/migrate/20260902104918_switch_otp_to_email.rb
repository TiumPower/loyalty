class SwitchOtpToEmail < ActiveRecord::Migration[7.2]
  def change
    add_column :otp_challenges, :email, :string
    change_column_null :otp_challenges, :phone, true
    change_column_null :members, :phone, true
    add_index :otp_challenges, [ :workspace_id, :email ]
  end
end
