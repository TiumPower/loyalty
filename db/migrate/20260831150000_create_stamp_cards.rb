class CreateStampCards < ActiveRecord::Migration[7.2]
  def change
    create_table :stamp_cards do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :reward,    null: true,  foreign_key: true # voucher issued on completion
      t.string  :title,        null: false
      t.text    :description
      t.string  :icon
      t.integer :target_count, null: false, default: 10
      t.boolean :active,       null: false, default: true
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :position,     null: false, default: 0
      t.timestamps
    end

    create_table :stamp_card_memberships do |t|
      t.references :workspace,  null: false, foreign_key: true
      t.references :member,     null: false, foreign_key: true
      t.references :stamp_card, null: false, foreign_key: true
      t.integer  :count,           null: false, default: 0
      t.integer  :completed_count, null: false, default: 0
      t.datetime :last_stamp_at
      t.timestamps
    end
    add_index :stamp_card_memberships, [ :member_id, :stamp_card_id ], unique: true
  end
end
