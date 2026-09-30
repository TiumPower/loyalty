class AddArchivedAtToRewards < ActiveRecord::Migration[7.2]
  def change
    add_column :rewards, :archived_at, :datetime
    add_index :rewards, [ :workspace_id, :archived_at ]
  end
end
