# Puts each campaign's existing banner into its new banner library.
#
# Two reasons this cannot be left to the app:
#
#   1. The library is what the merchant picks from. A campaign that already has
#      a banner should show it there from day one, not only after the next
#      upload.
#   2. `has_one_attached :banner` is now declared `dependent: false`, because
#      the current banner and the library share one blob and replacing the
#      banner must not delete a file the library still lists. Purging is the
#      library's job — so a banner that is NOT in the library would survive its
#      campaign being deleted and leak a file in storage forever.
#
# Written against the tables rather than the models: a data migration has to
# keep working after Campaign changes shape again.
class BackfillCampaignBannerLibrary < ActiveRecord::Migration[7.2]
  class MigrationBlob < ActiveRecord::Base
    self.table_name = "active_storage_blobs"
  end

  def up
    execute <<~SQL
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      SELECT 'banner_library', a.record_type, a.record_id, a.blob_id, a.created_at
      FROM active_storage_attachments a
      WHERE a.name = 'banner' AND a.record_type = 'Campaign'
        AND NOT EXISTS (
          SELECT 1 FROM active_storage_attachments b
          WHERE b.record_type = a.record_type AND b.record_id = a.record_id
            AND b.name = 'banner_library' AND b.blob_id = a.blob_id
        )
    SQL

    # Remember on the blob whether its image already carries a composited QR, so
    # re-selecting it from the library later restores the right answer. The
    # campaigns table holds that flag today; blobs.metadata is serialised JSON
    # text, so it is read and written in Ruby rather than with jsonb operators.
    rows = select_all(<<~SQL)
      SELECT a.blob_id AS blob_id, c.banner_has_qr AS has_qr
      FROM active_storage_attachments a
      JOIN campaigns c ON c.id = a.record_id
      WHERE a.name = 'banner' AND a.record_type = 'Campaign'
    SQL

    rows.each do |row|
      blob = MigrationBlob.find_by(id: row["blob_id"]) or next
      meta = begin
        JSON.parse(blob.metadata.presence || "{}")
      rescue JSON::ParserError
        {}
      end
      next unless meta["campaign_banner_qr"].nil?
      blob.update_columns(metadata: meta.merge("campaign_banner_qr" => !!row["has_qr"]).to_json)
    end
  end

  def down
    # Exact inverse: library entries that duplicate a campaign's current banner.
    # Files are left in place — a rollback is not a request to delete artwork.
    execute <<~SQL
      DELETE FROM active_storage_attachments lib
      WHERE lib.name = 'banner_library' AND lib.record_type = 'Campaign'
        AND EXISTS (
          SELECT 1 FROM active_storage_attachments cur
          WHERE cur.record_type = lib.record_type AND cur.record_id = lib.record_id
            AND cur.name = 'banner' AND cur.blob_id = lib.blob_id
        )
    SQL
  end
end
