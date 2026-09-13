module Merchant
  class DashboardController < BaseController
    include DateRangeFilterable

    before_action :require_manager!, only: [:rotate_checkin, :refresh_busy_hour]

    def show
      return redirect_to merchant_onboarding_path if current_workspace && !current_workspace.onboarded?
      @range = resolve_range
      # Staff locked to a branch always see only that branch.
      return load_branch_dashboard(scoped_outlet) if current_workspace && branch_scoped?
      # Owner/manager: a branch selector (Toàn merchant + each branch).
      @branches = current_workspace ? current_workspace.outlets.order(:name).to_a : []
      if current_workspace && params[:outlet].present? &&
         (chosen = @branches.find { |o| o.id.to_s == params[:outlet].to_s })
        return load_branch_dashboard(chosen)
      end
      @members_count   = current_workspace ? Member.count : 0
      @outlets_count   = current_workspace ? Outlet.count : 0
      @program         = current_program
      @tiers           = current_workspace ? current_workspace.tiers.ordered.to_a : []
      if current_workspace
        @points_issued   = in_range(PointTransaction.net_credits).sum(:amount)
        @points_redeemed = in_range(PointTransaction.redemptions).sum(:amount).abs
        @points_expired  = in_range(PointTransaction.expirations).sum(:amount).abs
        @points_outstanding = [Member.sum(:points_balance), 0].max # unredeemed = a liability (state, not range)
        @purchases_count = in_range(Purchase.not_voided).count
        @redemption_rate = @points_issued.zero? ? 0 : (@points_redeemed.to_f / @points_issued * 100).round
        # "Đang hoạt động" has to mean active. This counted lifetime_points > 0 —
        # anyone who ever earned a single point — so a shop where four fifths of
        # the list had not been back in a year still reported them all as active.
        @active_members  = Member.where(
          id: Purchase.not_voided.where("created_at >= ?", ACTIVE_WINDOW.ago).select(:member_id)
        ).count
        # Denominator for "điểm TB/khách": points issued is range-scoped, so the
        # customers it is divided by must be too, or picking a shorter range just
        # makes the average collapse against a lifetime member count.
        @earning_members = in_range(PointTransaction.net_credits).distinct.count(:member_id)
        # "Is this programme making me money?" — the numbers that answer it.
        @retention       = retention_metrics(Purchase.not_voided)
        @revenue         = @retention[:revenue]
        @new_sources     = new_member_sources
        @member_growth   = monthly_member_growth
        @tier_counts     = @tiers.map { |t| [t, Member.where(tier_key: t.key).count] }
        @outlet_stats    = build_outlet_stats
        load_busy_hour(nil) # busy-hour panel: all-merchant by default, own branch switcher
        # Check-in QR is per-branch only (see Outlets); the merchant no longer has
        # a workspace-level QR.
        @sub_warning     = subscription_warning(current_workspace)
      else
        @points_issued = @points_redeemed = @purchases_count = @redemption_rate = @active_members = 0
        @earning_members = 0
        @member_growth = []
        @tier_counts   = []
      end
    end

    # Downloadable, printable check-in QR (static workspace token).
    def checkin_qr
      url = helpers.customer_scan_url(current_workspace, checkin: Checkin.encode(current_workspace))
      send_data helpers.qr_png(url, size: 720),
                type: "image/png", disposition: "attachment",
                filename: "checkin-#{current_workspace.subdomain}.png"
    end

    # AJAX: return the busy-hour panel for the chosen branch + range (no reload).
    def busy_hour
      @range = resolve_range
      load_busy_hour(params[:outlet])
      render partial: "merchant/dashboard/busy_hour", layout: false
    end

    # AJAX: (re)generate the AI insight synchronously for the chosen branch, then
    # return the refreshed panel. Synchronous keeps it simple and reliable — no
    # background job to get stuck; the button shows a spinner while it runs.
    #
    # Synchronous also means each click is one Opus request held open on a web
    # thread, so the button is rate-limited and manager-only. Unguarded, anyone
    # with a staff login could hold it down and bill the account for it.
    REFRESH_COOLDOWN = 2.minutes
    def refresh_busy_hour
      @range = resolve_range
      load_busy_hour(params[:outlet])
      oid = @busy_outlet&.id
      if @busy_insight&.generated_at.present? && @busy_insight.generated_at > REFRESH_COOLDOWN.ago
        response.headers["X-Insight-Cooldown"] = "1"
        return render partial: "merchant/dashboard/busy_hour", layout: false
      end
      BusyHourInsight.new(current_workspace, matrix: @busy_hours, busiest_slot: @busiest_slot,
                          outlet: @busy_outlet, range: { from: @range[:from], to: @range[:to] }).generate!
      # reload the freshly-written insight
      @busy_insight = current_workspace.workspace_insights.find_by(kind: busy_hour_kind(oid))
      render partial: "merchant/dashboard/busy_hour", layout: false
    end

    # Rotate the check-in token: the old printed QR stops working immediately.
    # This is the only remedy for a poster that has been photographed and passed
    # around — and until now nothing in the app linked to it, so the machinery
    # was deployed with no way to reach it. Returns to the screen it was
    # triggered from (the branch QR screen, usually) rather than the dashboard.
    ROTATE_RETURN_PATHS = %w[/merchant/scan-home/checkin-qr /merchant/outlets].freeze
    def rotate_checkin
      current_workspace.rotate_checkin_nonce!
      redirect_to safe_rotate_return, notice: t("merchant.scan.checkin_rotated")
    end

    private

    # Date-range helpers (resolve_range / parse_range_date / in_range) are provided
    # by DateRangeFilterable. Flow metrics (points earned/redeemed, purchases, branch
    # performance) honour the range; state metrics (member count, outstanding
    # liability, tiers) stay lifetime.

    GRACE_DAYS = 10 # days after expiry before the workspace is locked
    ACTIVE_WINDOW = 90.days # "active" = bought within this window

    # created_at rendered in the shop's timezone (the column is naive UTC).
    LOCAL_CREATED_AT =
      "created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{Rails.application.config.time_zone}'".freeze

    # Returns a banner descriptor when the subscription needs attention, else nil.
    def subscription_warning(ws)
      pu = ws.paid_until
      return { kind: :inactive, level: :warn, days: nil } if pu.nil?
      left = (pu.to_date - Date.current).to_i
      if ws.trial?
        # Trial: nudge for the whole period (info), escalate to warn near the end.
        return { kind: :trial_over, level: :danger, days: [GRACE_DAYS + left, 0].max } if left < 0
        { kind: :trial, level: (left <= 3 ? :warn : :info), days: left }
      elsif left < 0
        { kind: :expired, level: :danger, days: [GRACE_DAYS + left, 0].max }
      elsif left <= 7
        { kind: :expiring, level: :warn, days: left }
      end
    end

    # Retention / spend economics over the active range, in two queries:
    #   buyers            — distinct customers who bought
    #   repeat_buyers     — of those, how many came back (2+ bills)
    #   repeat_rate       — the headline number a merchant renews on
    #   avg_bill          — average bill value
    #   per_buyer         — revenue per customer in the period
    #   visits_per_buyer  — average visits per customer
    def retention_metrics(base)
      scope = in_range(base)
      bills, buyers, revenue = scope.pick(
        Arel.sql("COUNT(*), COUNT(DISTINCT member_id), COALESCE(SUM(amount), 0)")
      )
      bills, buyers, revenue = bills.to_i, buyers.to_i, revenue.to_i
      # Counting the "2+ bills" group in SQL keeps this O(1) in memory even for a
      # workspace with tens of thousands of customers.
      inner  = scope.select(:member_id).group(:member_id).having("COUNT(*) >= 2").to_sql
      repeat = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM (#{inner}) t").to_i

      { bills: bills, buyers: buyers, revenue: revenue, repeat_buyers: repeat,
        repeat_rate:      buyers.zero? ? 0 : (repeat.to_f / buyers * 100).round,
        avg_bill:         bills.zero?  ? 0 : (revenue / bills),
        per_buyer:        buyers.zero? ? 0 : (revenue / buyers),
        visits_per_buyer: buyers.zero? ? 0 : (bills.to_f / buyers).round(1) }
    end

    # Where this period's new members came from. Rows created before attribution
    # existed have a NULL join_source and fold into "direct".
    def new_member_sources
      rows  = in_range(Member).group(:join_source).count
      total = rows.values.sum
      return { total: 0, rows: [] } if total.zero?
      list = Member::JOIN_SOURCES.filter_map do |key|
        n = rows[key].to_i
        n += rows[nil].to_i if key == "direct"
        next if n.zero?
        { key: key, count: n, pct: (n.to_f / total * 100).round }
      end
      { total: total, rows: list.sort_by { |r| -r[:count] } }
    end

    # New members per month over the last 6 months, with the running total.
    #
    # Months are cut in the shop's own timezone. created_at is a naive UTC
    # timestamp, so a plain date_trunc bucketed by UTC months: a customer who
    # signed up at 3am on the 1st (UTC+7) was reported under the PREVIOUS month,
    # and the month that had just started looked emptier than it was. The double
    # AT TIME ZONE reads the stored value as UTC, then converts it to local before
    # truncating — and the window boundary is a local month start for the same
    # reason, so the oldest bar isn't clipped.
    def monthly_member_growth
      months  = (0..5).map { |i| Time.zone.now.beginning_of_month - (5 - i).months } # oldest→newest
      raw     = Member.where("created_at >= ?", months.first)
                      .group(Arel.sql("date_trunc('month', #{LOCAL_CREATED_AT})")).count
      running = Member.where("created_at < ?", months.first).count
      months.map do |m|
        added = raw.find { |k, _| k.to_date == m.to_date }&.last.to_i
        running += added
        { label: I18n.l(m.to_date, format: "%m/%y"), value: added, total: running }
      end
    end

    # Branch-scoped dashboard: only this outlet's numbers.
    def load_branch_dashboard(outlet = scoped_outlet)
      @branch = outlet
      oid = @branch.id
      base = in_range(Purchase.not_voided.where(outlet_id: oid))
      @members_count   = base.distinct.count(:member_id)
      @points_issued   = base.sum(:points_earned)
      @purchases_count = base.count
      @revenue         = base.sum(:amount)
      vouchers = Voucher.where(used_outlet_id: oid, state: "used")
      @vouchers_used   = used_in_range(vouchers).count
      @retention       = retention_metrics(Purchase.not_voided.where(outlet_id: oid))
      render :show
    end

    # Vouchers are dated by used_at, not created_at.
    def used_in_range(rel)
      @range && @range[:from] ? rel.where(used_at: @range[:from]..@range[:to]) : rel
    end

    # Per-branch performance. Purchases and used vouchers are already tagged with
    # the outlet the staff belongs to, so we just group by outlet.
    def build_outlet_stats
      outlets   = current_workspace.outlets.order(:name).to_a
      scoped    = in_range(Purchase.not_voided)
      purchases = scoped.group(:outlet_id).count
      revenue   = scoped.group(:outlet_id).sum(:amount)
      points    = scoped.group(:outlet_id).sum(:points_earned)
      customers = scoped.distinct.group(:outlet_id).count(:member_id)
      vouchers  = used_in_range(Voucher.where(state: "used")).group(:used_outlet_id).count

      row = lambda do |id, name|
        { id: id, name: name, revenue: revenue[id].to_i, points: points[id].to_i,
          purchases: purchases[id].to_i, customers: customers[id].to_i, vouchers: vouchers[id].to_i }
      end
      rows = outlets.map { |o| row.call(o.id, o.name) }
      # Activity tagged to no outlet (staff without a branch, member self-scan).
      if purchases[nil].to_i.positive? || vouchers[nil].to_i.positive?
        rows << row.call(nil, "Chưa gán chi nhánh")
      end
      rows.sort_by { |r| -r[:revenue] }
    end

    # Activity by weekday × hour-of-day over the active range. Bucketed in Ruby
    # in the app timezone (Time.zone) so weekday + hour are locally correct —
    # created_at is stored in UTC. Returns [{ dow: 0..6, hours: [24 ints] }, ...]
    # (dow 0 = Sunday). Capped so a huge workspace can't load an unbounded set.
    BUSY_HOUR_SAMPLE_CAP = 50_000
    def busy_hour_matrix(outlet_id = nil)
      rows = (0..6).map { |dow| { dow: dow, hours: Array.new(24, 0) } }
      scope = in_range(Purchase.not_voided)
      scope = scope.where(outlet_id: outlet_id) if outlet_id.present?
      scope.order(created_at: :desc).limit(BUSY_HOUR_SAMPLE_CAP)
           .pluck(:created_at).each do |ts|
        t = ts.in_time_zone
        rows[t.wday][:hours][t.hour] += 1
      end
      rows
    end

    # Cache key (WorkspaceInsight#kind) for a busy-hour insight: workspace-wide,
    # or scoped to one branch.
    def busy_hour_kind(outlet_id) = outlet_id.present? ? "busy_hour_o#{outlet_id}" : "busy_hour"

    # Resolve the outlet chosen for the busy-hour panel (owner/manager only; branch
    # staff are locked to their own outlet), then load matrix + insight for it.
    def load_busy_hour(outlet_param)
      @busy_branches = branch_scoped? ? [] : current_workspace.outlets.order(:name).to_a
      @busy_outlet   = if branch_scoped?
        scoped_outlet
      elsif outlet_param.present?
        @busy_branches.find { |o| o.id.to_s == outlet_param.to_s }
      end
      oid = @busy_outlet&.id
      @busy_hours   = busy_hour_matrix(oid)
      @busiest_slot = busiest_slot(@busy_hours)
      @busy_insight = current_workspace.workspace_insights.find_by(kind: busy_hour_kind(oid))
    end

    # The single busiest weekday+hour cell (nil when there's no activity).
    def busiest_slot(matrix)
      best = nil
      matrix.each do |row|
        row[:hours].each_with_index do |c, hr|
          best = { dow: row[:dow], hour: hr, count: c } if c.positive? && (best.nil? || c > best[:count])
        end
      end
      best
    end

    # Only ever back to one of our own screens — never to a supplied URL.
    def safe_rotate_return
      back = URI.parse(request.referer.to_s).path rescue nil
      return back if back.present? && ROTATE_RETURN_PATHS.any? { |p| back.start_with?(p) }
      merchant_root_path
    end

    def nav_key = :dashboard
  end
end
