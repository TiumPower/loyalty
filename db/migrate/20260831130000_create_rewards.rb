class CreateRewards < ActiveRecord::Migration[7.2]
  def change
    create_table :rewards do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :title,       null: false
      t.text    :description
      t.string  :kind,        null: false, default: "voucher" # voucher/gift/discount
      t.string  :icon
      t.integer :cost_points                         # nil = free-issue only (claim-to-wallet, Phase 3)
      t.integer :value,        null: false, default: 0 # discount amount or % (per value_unit)
      t.string  :value_unit,   null: false, default: "vnd" # vnd / percent / item
      t.text    :terms
      t.integer :stock                                # nil = unlimited
      t.integer :redeemed_count, null: false, default: 0
      t.integer :valid_days,   null: false, default: 30 # voucher lifetime once issued
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active,      null: false, default: true
      t.integer :position,    null: false, default: 0

      t.timestamps
    end

    add_index :rewards, [ :workspace_id, :active, :position ]
  end
end
