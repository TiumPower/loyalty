module Merchant
  class CustomersController < BaseController
    before_action :set_member, only: [:show, :adjust, :destroy, :merge, :merge_into]
    before_action :require_manager!, only: [:adjust]
    # Merging is as destructive and as irreversible as deleting, so it sits
    # behind the same gate.
    before_action :require_owner!, only: [:destroy, :merge, :merge_into]

    PER_PAGE = 50

    def index
      @segment = MemberSegments::PRESETS.key?(params[:segment]) ? params[:segment] : "all"
      @counts  = MemberSegments.counts
      @q, @sort = params[:q].to_s.strip, params[:sort]
      @tiers = current_workspace.tiers.ordered.to_a
      @tier  = params[:tier].presence if @tiers.any? { |t| t.key == params[:tier] }

      if branch_scoped?
        # Branch staff only see customers who transacted at their outlet.
        @applied_outlet = scoped_outlet
      else
        # Owner/manager: optional branch filter (Toàn merchant vs a branch).
        @branches = current_workspace.outlets.order(:name).to_a
        @outlet = @branches.find { |x| x.id.to_s == params[:outlet].to_s } if params[:outlet].present?
        @applied_outlet = @outlet
      end

      base = MemberSegments.audience(segment: @segment, outlet_id: @applied_outlet&.id, q: @q, tier: @tier)
      @total = base.count # count on the ungrouped scope (sort may GROUP BY for "spend")
      @page  = [params[:page].to_i, 1].max
      @members  = apply_sort(base, @sort).limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
      @has_more = @total > @page * PER_PAGE

      # Visits and last visit for the table, in one grouped query rather than
      # two per row.
      ids = @members.map(&:id)
      if ids.any?
        rows = Purchase.not_voided.where(member_id: ids).group(:member_id)
                       .pluck(Arel.sql("member_id, COUNT(*), MAX(created_at)"))
        @visits = rows.to_h { |mid, n, last| [mid, { count: n.to_i, last: last }] }
      end
      @visits ||= {}

      # The design keeps a quick-preview panel beside the table; which customer
      # it shows lives in the URL so the view is shareable and survives paging.
      @preview = @members.find { |m| m.id.to_s == params[:preview].to_s } || @members.first
      if @preview
        @preview_purchases = @preview.purchases.not_voided.order(created_at: :desc).limit(2).to_a
      end

      # Filters to carry into "Soạn thông báo" so the broadcast targets exactly the
      # audience shown here (segment + branch + tier + search), not the whole segment.
      @compose_params = { segment: @segment, outlet: @applied_outlet&.id, tier: @tier, q: @q.presence }.compact
    end

    # The audiences the shop can target, with what each rule means and who is
    # currently in it. The rules are live, so every number here is computed now
    # rather than stored — which is also why there is no "trend" column.
    def segments
      @tiers  = current_workspace.tiers.ordered.to_a
      @counts = MemberSegments.counts
      @keys   = MemberSegments::PRESETS.keys
      @key    = MemberSegments::PRESETS.key?(params[:key]) ? params[:key] : @keys.first
      scope   = MemberSegments.audience(segment: @key)
      @sample = scope.order(points_balance: :desc).limit(3).to_a
      @size   = @counts[@key].to_i
      # Tier mix of the selected audience — "who is in here" in one glance.
      counts_by_tier = scope.group(:tier_key).count
      @mix = @tiers.map { |t| [t, counts_by_tier[t.key].to_i] }
    end

    def show
      @transactions   = @member.point_transactions.recent.includes(:outlet, :staff).limit(50).to_a
      @vouchers       = @member.vouchers.recent.includes(:reward).limit(20).to_a
      @purchase_count = @member.purchases.not_voided.count
      @total_spend    = @member.purchases.not_voided.sum(:amount)
    end

    # Manual points correction: comp points, fix a mistake, or gift an apology.
    # Points are a liability the shop owes, and this writes straight to the
    # ledger with no purchase behind it, so it is fenced on three sides.
    MAX_ADJUST = 1_000_000
    MAX_NOTE   = 140 # the reason is printed on the customer's own history screen

    def adjust
      amount = params[:amount].to_s.gsub(/[^\d-]/, "").to_i
      note   = params[:note].to_s.strip

      if amount.zero?
        return reject_adjust("Vui lòng nhập số điểm khác 0.")
      end
      # An unexplained manual override is the one nobody can account for later.
      if note.blank?
        return reject_adjust("Vui lòng nhập lý do điều chỉnh — lý do hiển thị trong lịch sử của khách.")
      end
      if note.length > MAX_NOTE
        return reject_adjust("Lý do quá dài (tối đa #{MAX_NOTE} ký tự) — lý do này hiển thị trong lịch sử của khách.")
      end
      # One stray keystroke on a 50-point comp used to mint fifty million.
      if amount.abs > MAX_ADJUST
        return reject_adjust("Số điểm vượt giới hạn một lần (#{helpers.number_with_delimiter(MAX_ADJUST)}). " \
                             "Hãy chia nhỏ hoặc kiểm tra lại con số.")
      end
      # Deducting more than the customer holds used to drive the balance
      # NEGATIVE — the app then showed them "-49.999.949 điểm" and every tier,
      # redemption and expiry calculation ran on a number that cannot exist.
      if amount.negative? && amount.abs > @member.points_balance.to_i
        return reject_adjust("Khách chỉ còn #{helpers.number_with_delimiter(@member.points_balance)} điểm — " \
                             "không thể trừ nhiều hơn số điểm đang có.")
      end

      @member.point_transactions.create!(workspace: current_workspace, kind: "adjust",
                                         amount: amount, note: note, staff: current_user)
      @member.recompute_points!
      verb = amount.positive? ? "cộng" : "trừ"
      redirect_to merchant_customer_path(@member),
                  notice: "Đã #{verb} #{helpers.number_with_delimiter(amount.abs)} điểm cho #{@member.display_name}."
    end

    # Permanently remove a customer and all their data (points ledger, vouchers,
    # stamps, badges, notifications…). Owner-only, irreversible — confirmed in the UI.
    def destroy
      name = @member.display_name
      @member.destroy!
      redirect_to merchant_customers_path, notice: "Đã xoá khách hàng #{name}."
    end

    # Phone login matches on (workspace, phone), so a customer who used to sign
    # in by email and now signs in by phone can end up with two profiles. This
    # screen picks the duplicate, then shows exactly what will move before
    # anything is touched.
    def merge
      @candidates = Member.likely_duplicates_of(@member, q: params[:q])
      @other      = Member.find_by(id: params[:with]) if params[:with].present?
      @summary    = MemberMerge.preview(keeper: @member, loser: @other) if @other
    end

    def merge_into
      other = Member.find_by(id: params[:with])
      return redirect_to merge_merchant_customer_path(@member), alert: "Chưa chọn hồ sơ để gộp." if other.nil?

      result = MemberMerge.call(keeper: @member, loser: other, actor: current_user)
      if result.ok?
        redirect_to merchant_customer_path(@member),
                    notice: "Đã gộp hồ sơ vào #{@member.reload.display_name}."
      else
        redirect_to merge_merchant_customer_path(@member, with: other.id),
                    alert: "Không gộp được: #{result.error}"
      end
    end

    private

    def reject_adjust(message)
      redirect_to merchant_customer_path(@member), alert: message
    end

    def nav_key = (action_name == "segments" ? :segments : :customers)

    def set_member
      @member = Member.find(params[:id])
    end

    def apply_sort(scope, sort)
      case sort
      when "points" then scope.order(points_balance: :desc)
      when "spend"
        scope.left_joins(:purchases).group("members.id")
             .order(Arel.sql("COALESCE(SUM(CASE WHEN purchases.voided_at IS NULL THEN purchases.amount ELSE 0 END), 0) DESC"))
      else scope.order(created_at: :desc)
      end
    end
  end
end
