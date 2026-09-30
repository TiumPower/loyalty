class CreateRatings < ActiveRecord::Migration[7.2]
  def change
    create_table :ratings do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.references :outlet, foreign_key: true
      t.integer :stars, null: false, default: 5
      t.text :comment
      t.timestamps
    end
    add_index :ratings, [ :workspace_id, :member_id ], unique: true
  end
end
