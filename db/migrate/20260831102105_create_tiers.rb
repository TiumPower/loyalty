class CreateTiers < ActiveRecord::Migration[7.2]
  def change
    create_table :tiers do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :key,              null: false            # bronze / silver / gold / diamond
      t.string  :name,             null: false
      t.integer :threshold_points, null: false, default: 0
      t.decimal :multiplier,       null: false, default: 1.0, precision: 4, scale: 2
      t.jsonb   :benefits,         null: false, default: []
      t.string  :gradient_from
      t.string  :gradient_to
      t.integer :position,         null: false, default: 0

      t.timestamps
    end

    add_index :tiers, [ :workspace_id, :key ], unique: true
    add_index :tiers, [ :workspace_id, :position ]
  end
end
