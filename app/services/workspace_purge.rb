# Hard-deletes a workspace and every row that belongs to it. All tenant tables
# carry workspace_id, so we delete by that in FK-safe order (children first)
# rather than relying on ActiveRecord cascades — guaranteed no orphan / FK error.
class WorkspacePurge
  # Order matters: a table must be listed before any table it references.
  DELETE_ORDER = %w[
    pos_charges promo_claims spin_logs mission_progresses member_badges
    stamp_card_memberships notifications ratings push_subscriptions
    point_transactions purchases vouchers referrals memberships members
    promo_codes campaigns stamp_cards missions badges rewards outlets
    tiers spin_wheels invoices loyalty_programs otp_challenges broadcasts
    merchant_alerts workspace_insights
  ].freeze

  def self.call(workspace)
    ActsAsTenant.without_tenant do
      ApplicationRecord.transaction do
        wid = workspace.id
        # Purge Active Storage first so blobs/files don't orphan.
        purge_attachments("Workspace", [ wid ])
        member_ids = Member.where(workspace_id: wid).pluck(:id)
        purge_attachments("Member", member_ids) if member_ids.any?

        conn = ApplicationRecord.connection
        DELETE_ORDER.each do |table|
          conn.exec_delete("DELETE FROM #{table} WHERE workspace_id = #{wid.to_i}", "WorkspacePurge")
        end
        workspace.destroy!
      end
    end
  end

  def self.purge_attachments(record_type, ids)
    ActiveStorage::Attachment.where(record_type: record_type, record_id: ids).find_each(&:purge)
  end
end
