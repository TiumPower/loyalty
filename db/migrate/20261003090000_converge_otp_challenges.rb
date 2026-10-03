# Bring otp_challenges onto the shape shared by the sibling apps: ONE identifier
# column holding either an email or a phone, plus the channel the code goes out
# on. Phone+OTP login needs a challenge that is not keyed by email, and a single
# shape means one delivery layer serves all three apps.
#
# `identifier` stays NULLABLE here on purpose: Capistrano runs deploy:migrate
# while the OLD code is still serving requests, and the old code inserts rows
# without it. The NOT NULL lands in a later cleanup migration, together with
# dropping the legacy columns.
class ConvergeOtpChallenges < ActiveRecord::Migration[7.2]
  def up
    add_column :otp_challenges, :identifier, :string
    add_column :otp_challenges, :channel, :string, default: "email", null: false
    add_column :otp_challenges, :scope,   :string, default: "customer", null: false
    add_column :otp_challenges, :delivered_at,      :datetime
    add_column :otp_challenges, :delivery_provider, :string
    add_column :otp_challenges, :delivery_error,    :string

    execute <<~SQL
      UPDATE otp_challenges
         SET identifier = COALESCE(NULLIF(email, ''), NULLIF(phone, '')),
             channel    = CASE WHEN COALESCE(email, '') <> '' THEN 'email' ELSE 'zalo' END
       WHERE identifier IS NULL
    SQL

    add_index :otp_challenges, [:workspace_id, :identifier]
    add_index :otp_challenges, [:scope, :identifier]

    # The `phone` column was never written by any call site, so this index has
    # only ever indexed NULLs.
    remove_index :otp_challenges, column: [:workspace_id, :phone, :purpose]

    # Deliberately interrupt challenges still in flight rather than leave rows
    # the new code cannot find. The TTL is 10 minutes and the login screen can
    # re-issue, so the worst case is one extra tap during the deploy.
    execute "DELETE FROM otp_challenges WHERE consumed_at IS NULL"
  end

  def down
    remove_index :otp_challenges, column: [:scope, :identifier]
    remove_index :otp_challenges, column: [:workspace_id, :identifier]
    add_index :otp_challenges, [:workspace_id, :phone, :purpose]
    remove_column :otp_challenges, :delivery_error
    remove_column :otp_challenges, :delivery_provider
    remove_column :otp_challenges, :delivered_at
    remove_column :otp_challenges, :scope
    remove_column :otp_challenges, :channel
    remove_column :otp_challenges, :identifier
  end
end
