class AddIdempotencyKeyToPurchases < ActiveRecord::Migration[7.2]
  # Awarding points had no exactly-once guarantee: every POST to /merchant/earn
  # created another Purchase, so a second tap at the counter — a slow network,
  # an impatient cashier, a back-button resubmit — paid the customer twice.
  # The scanner now sends a token minted when the customer was looked up, and
  # this index is what actually enforces it.
  def change
    add_column :purchases, :idempotency_key, :string
    add_index :purchases, [:workspace_id, :idempotency_key],
              unique: true, where: "idempotency_key IS NOT NULL",
              name: "index_purchases_on_workspace_and_idempotency_key"
  end
end
