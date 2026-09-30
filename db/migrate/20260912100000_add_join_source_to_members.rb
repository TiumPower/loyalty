class AddJoinSourceToMembers < ActiveRecord::Migration[7.2]
  def up
    add_column :members, :join_source, :string
    add_index  :members, [ :workspace_id, :join_source ]
    # Backfill: anyone with a referrer came in through the referral link; the
    # rest are unattributed history ("direct").
    execute <<~SQL
      UPDATE members SET join_source = CASE
        WHEN referred_by_id IS NOT NULL THEN 'referral' ELSE 'direct' END
      WHERE join_source IS NULL
    SQL
  end

  def down
    remove_index  :members, [ :workspace_id, :join_source ]
    remove_column :members, :join_source
  end
end
