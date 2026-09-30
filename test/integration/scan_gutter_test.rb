require "test_helper"

# Every scan outcome screen ends in a "Về trang chủ" button, and the tab bar
# floats over the bottom of the app. These screens carried `l-screen no-tabs` —
# the short gutter meant for screens that hide the bar — while still rendering
# it, so the last button sat underneath the bar with no scroll left to reach it.
class ScanGutterTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "gutter")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Thảo Điền", active: true)
      @ws.missions.create!(title: "Điểm danh", mission_type: "checkin", period: "daily",
                           goal: 1, reward_points: 20, position: 0, active: true)
      @member = create(:member, workspace: @ws, email: "gutter@example.com")
      reward  = create(:reward, workspace: @ws, cost_points: nil, valid_days: 30)
      @promo  = @ws.promo_codes.create!(reward: reward, active: true, max_claims: 10)
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email).order(:id).last.code
    }
  end

  def base = "/w/#{@ws.slug}"

  # The contradiction itself, swept over every screen the scanner can land on:
  # a screen either hides the bar and may use the short gutter, or shows the bar
  # and must leave the full one. Never the short gutter under a visible bar.
  test "no scan screen uses the short gutter while the tab bar floats over it" do
    checkin = ActsAsTenant.with_tenant(@ws) { Checkin.encode(@ws, @outlet) }
    screens = {
      "the scanner"          => "#{base}/scan",
      "check-in success"     => "#{base}/scan/resolve?checkin=#{CGI.escape(checkin)}",
      "an invalid code"      => "#{base}/scan/resolve?code=NOPE-NOPE",
      "the gift claim"       => "#{base}/scan/resolve?promo=#{CGI.escape(@promo.token)}",
    }

    screens.each do |what, url|
      get url
      assert_includes 200..499, response.status, "#{what} should render"
      tabbar = css_select(".l-tabbar").any?
      short  = css_select(".l-screen.no-tabs").any?
      refute(tabbar && short,
             "#{what} floats the tab bar over a screen using the short gutter: " \
             "the last button ends up underneath it")
    end
  end

  # The camera does two jobs; the screen used to name only one of them.
  test "the scanner says a campaign gift can be claimed with it, not just check-in" do
    get "#{base}/scan"
    assert_response :success
    assert_match I18n.t("customer.scan.campaign_gift"), response.body
    assert_match I18n.t("customer.scan.campaign_explainer"), response.body
  end

  # "Để nhận điểm" is not a reason to open a camera. The design names a number.
  test "the scanner says what a check-in is actually worth" do
    get "#{base}/scan"
    assert_response :success
    assert_match I18n.t("customer.scan.what_you_earn"), response.body
    assert_match "20", response.body
    assert_match I18n.t("customer.scan.once_a_day"), response.body

    # After today's check-in the same row has to stop inviting one.
    checkin = ActsAsTenant.with_tenant(@ws) { Checkin.encode(@ws, @outlet) }
    get "#{base}/scan/resolve", params: { checkin: checkin }
    get "#{base}/scan"
    assert_match I18n.t("customer.scan.done_today"), response.body
    refute_match I18n.t("customer.scan.once_a_day"), response.body
  end

  test "the my-code sheet's scan button says what else the camera is for" do
    get "#{base}/my-code"
    assert_response :success
    assert_select "a[href=?].l-btn", "#{base}/scan", 1,
                  "the way to the camera should be a button, not a text link"
    assert_match I18n.t("customer.my_code.scan_shop_qr_sub"), response.body
  end

  # Receiving a gift is a small celebration; the screen was showing the same
  # gift box the wallet uses for the thing itself.
  test "claiming a gift is congratulated, not just illustrated with a gift box" do
    get "#{base}/scan/resolve", params: { promo: @promo.token }
    assert_response :success
    assert_select ".l-result .halo.solid", 1
  end
end
