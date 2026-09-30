class CreateCampaigns < ActiveRecord::Migration[7.2]
  def change
    create_table :campaigns do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :reward,    null: true,  foreign_key: true

      t.string  :name,          null: false
      t.string  :campaign_type, null: false, default: "promo_voucher"
      # promo_voucher / double_points / happy_hour / event / flash_mission
      t.string  :status,        null: false, default: "draft"
      # draft / scheduled / running / paused / ended
      t.string  :audience,      null: false, default: "all"
      # all / vip / new / at_risk / birthday
      t.datetime :starts_at
      t.datetime :ends_at
      t.jsonb   :content,  null: false, default: {} # title/body/banner/tone
      t.jsonb   :metrics,  null: false, default: {}

      t.timestamps
    end

    add_index :campaigns, [ :workspace_id, :status ]
  end
end
