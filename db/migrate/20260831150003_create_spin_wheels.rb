class CreateSpinWheels < ActiveRecord::Migration[7.2]
  def change
    create_table :spin_wheels do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.jsonb   :segments,   null: false, default: [] # [{label,kind,value,weight,color}]
      t.boolean :daily_free, null: false, default: true
      t.integer :cost_points, null: false, default: 100 # cost for extra spins
      t.boolean :active,     null: false, default: true
      t.timestamps
    end

    create_table :spin_logs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member,    null: false, foreign_key: true
      t.integer :segment_index
      t.string  :result_kind        # points/voucher/none
      t.integer :result_value, null: false, default: 0
      t.integer :cost,         null: false, default: 0
      t.references :voucher, null: true, foreign_key: true
      t.timestamps
    end
    add_index :spin_logs, [ :member_id, :created_at ]
  end
end
