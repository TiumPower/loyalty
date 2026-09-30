class CreateWorkspaceInsights < ActiveRecord::Migration[7.2]
  def change
    create_table :workspace_insights do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string   :kind, null: false          # e.g. "busy_hour"
      t.text     :body                        # the AI-generated suggestion
      t.datetime :range_from
      t.datetime :range_to
      t.datetime :generated_at
      t.string   :status, default: "ready", null: false # ready | generating
      t.timestamps
    end
    add_index :workspace_insights, [ :workspace_id, :kind ], unique: true
  end
end
