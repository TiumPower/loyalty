module Admin
  class MonitoringController < BaseController
    def show
      ActsAsTenant.without_tenant do
        @workspace_count = Workspace.count
        @by_status       = Workspace.group(:status).count
        @members_count   = Member.count
        @points_issued   = PointTransaction.credits.sum(:amount)
        @points_redeemed = PointTransaction.debits.sum(:amount).abs
        @purchases_count = Purchase.not_voided.count
        @vouchers_used   = Voucher.where(state: "used").count

        # Top workspaces by member count
        counts = Member.group(:workspace_id).count
        @top = Workspace.where(id: counts.keys).to_a
                        .sort_by { |w| -counts[w.id].to_i }.first(6)
                        .map { |w| [ w, counts[w.id].to_i ] }

        # Simple anomaly flags
        @alerts = []
        @by_status.fetch("past_due", 0).then { |n| @alerts << "#{n} workspace quá hạn thanh toán" if n.positive? }
        @by_status.fetch("pending", 0).then { |n| @alerts << "#{n} workspace đang chờ duyệt" if n.positive? }
      end
    end

    private

    def nav_key = :monitoring
  end
end
