require "test_helper"

# Every page a merchant / admin can reach should render, not 500.
class PageSmokeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "smoke")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      WorkspaceBootstrap.call(@ws) if defined?(WorkspaceBootstrap)
    end
    sign_in @user
  end

  MERCHANT_PAGES = %w[
    /merchant /merchant/account /merchant/onboarding /merchant/choose
    /merchant/outlets
    /merchant/customers /merchant/transactions
    /merchant/rewards /merchant/rewards/new
    /merchant/campaigns /merchant/campaigns/new
    /merchant/broadcasts /merchant/broadcasts/new
    /merchant/program /merchant/gamification
    /merchant/feedback /merchant/automations /merchant/alerts
    /merchant/staff /merchant/domain /merchant/appearance
    /merchant/billing /merchant/checkin_qr /merchant/quick_login_qr
    /merchant/scanner /merchant/scan-home
    /merchant/mission_submissions
  ].freeze

  MERCHANT_PAGES.each do |path|
    test "GET #{path} renders" do
      get path
      assert_includes [200, 302], response.status, "#{path} returned #{response.status}"
    end
  end
end

class AdminPageSmokeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "adminsmoke")
    sign_in create(:admin_user), scope: :admin_user
  end

  ADMIN_PAGES = %w[
    /admin /admin/workspaces /admin/workspaces/new
    /admin/billing /admin/plans /admin/account /admin/monitoring
  ].freeze

  ADMIN_PAGES.each do |path|
    test "GET #{path} renders" do
      get path
      assert_includes [200, 302], response.status, "#{path} returned #{response.status}"
    end
  end

  test "a workspace detail page renders" do
    get "/admin/workspaces/#{@ws.to_param}"
    assert_response :success
  end

  # The dashboard shipped with these hardcoded to 0 and a "Phase 1+" caption,
  # so the operator's first screen disagreed with /admin/monitoring.
  test "the dashboard reports the same points as monitoring" do
    ActsAsTenant.with_tenant(@ws) do
      member = create(:member, workspace: @ws)
      PointTransaction.create!(workspace: @ws, member: member, kind: "earn", amount: 1234)
    end

    get "/admin"
    assert_response :success
    assert_match "1.234", response.body, "the dashboard is not counting points"

    get "/admin/monitoring"
    assert_match "1.234", response.body
  end

  test "no development placeholder is left on the dashboard" do
    get "/admin"
    assert_no_match(/Phase 1\+/, response.body)
  end

  test "plans show how many workspaces a change would affect" do
    create(:workspace, subdomain: "onstarter", plan: "starter")
    get "/admin/plans"
    assert_response :success
    assert_match(/workspace đang dùng gói này/, response.body)
  end
end
