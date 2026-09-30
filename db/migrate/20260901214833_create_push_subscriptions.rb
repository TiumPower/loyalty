class CreatePushSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :push_subscriptions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.timestamps
    end
    add_index :push_subscriptions, [ :member_id, :endpoint ], unique: true
  end
end
