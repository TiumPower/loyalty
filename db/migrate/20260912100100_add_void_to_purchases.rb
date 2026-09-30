class AddVoidToPurchases < ActiveRecord::Migration[7.2]
  def change
    add_column :purchases, :voided_at,   :datetime
    add_column :purchases, :void_reason, :string
    add_reference :purchases, :voided_by, foreign_key: { to_table: :users }
    # Every revenue/stat query filters on "not voided" — keep it cheap.
    add_index :purchases, [ :workspace_id, :voided_at ]
  end
end
