require "test_helper"
require "minitest/mock"

# The dashboard is the report a merchant renews (or cancels) on, so the figures
# it prints have to mean what their labels say.
class DashboardReportingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws    = create(:workspace)
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @owner = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 1000, tiers_enabled: false)
      @ws.memberships.create!(user: @owner, role: "owner")
      @member = create(:member, workspace: @ws)
    end
  end

  # ExpirePoints writes a negative "expire" row when a shop runs an expiry
  # window. It was swept up by the `redemptions` scope, so points that quietly
  # lapsed were reported as points customers had spent — and the redemption
  # rate, the number the whole programme is judged on, was inflated with them.
  test "expired points are not counted as redemptions" do
    ActsAsTenant.with_tenant(@ws) do
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 500)
      @member.point_transactions.create!(workspace: @ws, kind: "redeem", amount: -100)
      @member.point_transactions.create!(workspace: @ws, kind: "expire", amount: -300, note: "Điểm hết hạn")

      assert_equal 100, PointTransaction.redemptions.sum(:amount).abs
      assert_equal 300, PointTransaction.expirations.sum(:amount).abs
      assert_equal 500, PointTransaction.net_credits.sum(:amount)
    end

    sign_in @owner
    get merchant_root_path
    assert_response :success
    assert_match "tỷ lệ đổi 20%", response.body            # 100 of 500
    refute_match "tỷ lệ đổi 80%", response.body            # 100 + 300 expired
    assert_match "300 điểm hết hạn", response.body         # reported on its own
  end

  # created_at is stored as naive UTC. Bucketing the growth chart with a plain
  # date_trunc cut months at 00:00 UTC = 07:00 in Asia/Ho_Chi_Minh, so an
  # early-morning signup on the 1st was charted under the previous month.
  test "member growth buckets months in the shop timezone" do
    first_of_month = Time.zone.now.beginning_of_month + 3.hours
    skip "needs a month boundary in range" if first_of_month > Time.current

    ActsAsTenant.with_tenant(@ws) do
      early = create(:member, workspace: @ws)
      early.update_column(:created_at, first_of_month)
    end

    sign_in @owner
    get merchant_root_path
    assert_response :success

    ctrl = Merchant::DashboardController.new
    ctrl.instance_variable_set(:@range, nil)
    rows = ActsAsTenant.with_tenant(@ws) { ctrl.send(:monthly_member_growth) }
    this_month = rows.last
    assert_equal I18n.l(Time.zone.today.beginning_of_month, format: "%m/%y"), this_month[:label]
    assert_equal 2, this_month[:value],
                 "a 03:00 signup on the 1st belongs to this month, not the last"
    assert_equal Member.unscoped.where(workspace: @ws).count, this_month[:total]
  end

  # "Đang hoạt động" counted lifetime_points > 0 — anyone who had ever earned a
  # point, including a customer last seen two years ago.
  test "active members means recently active, not ever-active" do
    ActsAsTenant.with_tenant(@ws) do
      lapsed = create(:member, workspace: @ws)
      EarnPoints.new(member: lapsed, amount: 50_000, staff: @owner).call
      Purchase.where(member_id: lapsed.id).update_all(created_at: 200.days.ago)
      EarnPoints.new(member: @member, amount: 50_000, staff: @owner).call

      assert_equal 2, Member.where("lifetime_points > 0").count, "both have earned at some point"
    end

    sign_in @owner
    get merchant_root_path
    assert_response :success
    assert_match "1 hoạt động (90 ngày)", response.body
  end

  # Each refresh is a synchronous Opus call billed to the account, so it is
  # manager-only and rate limited.
  test "busy-hour refresh is manager-only and rate limited" do
    cashier = create(:user)
    ActsAsTenant.with_tenant(@ws) { @ws.memberships.create!(user: cashier, role: "staff") }

    sign_in cashier
    post merchant_refresh_busy_hour_insight_path
    assert_redirected_to merchant_root_path
    sign_out cashier

    ActsAsTenant.with_tenant(@ws) do
      @ws.workspace_insights.create!(kind: "busy_hour", body: "cũ", status: "ready",
                                    generated_at: 10.seconds.ago)
    end

    sign_in @owner
    ClaudeService.stub :safe_call, ->(*, **, &_b) { flunk("model must not be called during cooldown") } do
      post merchant_refresh_busy_hour_insight_path
    end
    assert_response :success
    assert_equal "1", response.headers["X-Insight-Cooldown"]
    assert_equal "cũ", ActsAsTenant.with_tenant(@ws) { @ws.workspace_insights.find_by(kind: "busy_hour").body }
  end
end
