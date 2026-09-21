class AddBannerHasQrToCampaigns < ActiveRecord::Migration[7.2]
  def up
    add_column :campaigns, :banner_has_qr, :boolean, default: false, null: false
    # Every banner generated before this column existed had the QR composited in
    # unconditionally, so the public page must keep hiding its standalone QR.
    execute <<~SQL
      UPDATE campaigns SET banner_has_qr = TRUE
      WHERE banner_status = 'ready'
    SQL
  end

  def down
    remove_column :campaigns, :banner_has_qr
  end
end
