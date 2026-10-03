module Admin
  class DashboardController < BaseController
    # Màn hình đầu tiên của người vận hành nền tảng.
    #
    # Trước đây nội dung này nằm ở HAI trang: "Tổng quan" và "Giám sát". Ba ô
    # đầu của chúng trùng nhau từng con số, và cảnh báo thì hiện ở trang Giám
    # sát trong khi Tổng quan chỉ đếm số cảnh báo rồi dẫn sang đó — tức là phải
    # bấm thêm một nhịp mới biết cảnh báo nói gì. Gộp lại một trang.
    def show
      ActsAsTenant.without_tenant do
        @workspaces_count = Workspace.count
        @by_status        = Workspace.group(:status).count
        @active_count     = @by_status.fetch("active", 0)
        @trial_count      = @by_status.fetch("trial", 0)
        @members_count    = Member.count
        # Hai KPI này từng bị ghim cứng bằng 0 kèm chú thích "Phase 1+" — một
        # mẩu code dang dở đã lên production, nên màn hình đầu tiên của người
        # vận hành báo không có điểm nào được phát trên một nền tảng đã phát
        # 83.767 điểm.
        @points_issued    = PointTransaction.credits.sum(:amount)
        @points_redeemed  = PointTransaction.debits.sum(:amount).abs
        @purchases_count  = Purchase.not_voided.count
        @vouchers_used    = Voucher.where(state: "used").count
        @recent           = Workspace.order(created_at: :desc).limit(8).to_a

        counts = Member.group(:workspace_id).count
        @top = Workspace.where(id: counts.keys).to_a
                        .sort_by { |w| -counts[w.id].to_i }.first(6)
                        .map { |w| [w, counts[w.id].to_i] }

        @alerts = []
        @by_status.fetch("past_due", 0).then { |n| @alerts << "#{n} workspace quá hạn thanh toán" if n.positive? }
        @by_status.fetch("pending", 0).then  { |n| @alerts << "#{n} workspace đang chờ duyệt" if n.positive? }
      end
    end

    private

    def nav_key = :dashboard
  end
end
