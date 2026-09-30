class CreateMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :memberships do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :outlet,    null: true,  foreign_key: true
      t.string  :role,   null: false, default: "staff" # owner / manager / staff / cashier
      t.string  :status, null: false, default: "active" # active / invited / suspended

      t.timestamps
    end

    add_index :memberships, [ :user_id, :workspace_id ], unique: true
  end
end
