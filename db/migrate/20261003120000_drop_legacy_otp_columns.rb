# Cleanup half of the identifier/channel move. MUST be deployed in a LATER
# release than the one that added `ignored_columns` to OtpChallenge: Capistrano
# runs deploy:migrate while the old puma is still serving, and a process whose
# schema cache still lists `email` builds every INSERT with it.
#
# `phone` was already dead before any of this — no call site ever wrote it.
class DropLegacyOtpColumns < ActiveRecord::Migration[7.2]
  def up
    # Rows from before the backfill, or written by a process that predates it.
    # The table holds minutes of data, so there is nothing here worth keeping.
    execute "DELETE FROM otp_challenges WHERE identifier IS NULL"
    change_column_null :otp_challenges, :identifier, false

    remove_index  :otp_challenges, column: [:workspace_id, :email]
    remove_column :otp_challenges, :email
    remove_column :otp_challenges, :phone
  end

  # Structure only — the identifiers that lived in these columns are gone, and
  # a ten-minute-TTL table has nothing worth restoring anyway.
  def down
    add_column :otp_challenges, :email, :string
    add_column :otp_challenges, :phone, :string
    add_index  :otp_challenges, [:workspace_id, :email]
    change_column_null :otp_challenges, :identifier, true
  end
end
