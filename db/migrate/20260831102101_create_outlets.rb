class CreateOutlets < ActiveRecord::Migration[7.2]
  def change
    create_table :outlets do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :name,    null: false
      t.string  :code
      t.string  :address
      t.string  :phone
      t.boolean :active,  null: false, default: true
      t.jsonb   :settings, null: false, default: {}

      t.timestamps
    end

    add_index :outlets, [ :workspace_id, :code ], unique: true, where: "code IS NOT NULL"
  end
end
