class AllowMultipleRatings < ActiveRecord::Migration[7.2]
  def change
    remove_index :ratings, column: [ :workspace_id, :member_id ], unique: true, if_exists: true
    add_index :ratings, [ :workspace_id, :member_id ]
  end
end
