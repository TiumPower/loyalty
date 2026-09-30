class CreateMerchantAlerts < ActiveRecord::Migration[7.2]
  def change
    create_table :merchant_alerts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string   :kind,  null: false
      t.string   :title, null: false
      t.text     :body
      t.string   :icon
      t.string   :link
      t.string   :level, null: false, default: "info" # info | warn | danger
      t.string   :dedup_key                            # collapses repeats
      t.datetime :read_at
      t.timestamps
    end
    add_index :merchant_alerts, [ :workspace_id, :created_at ]
    add_index :merchant_alerts, [ :workspace_id, :read_at ]
    add_index :merchant_alerts, [ :workspace_id, :dedup_key ], unique: true,
              where: "dedup_key IS NOT NULL"
  end
end
