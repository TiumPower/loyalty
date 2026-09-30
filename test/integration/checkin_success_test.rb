require "test_helper"

# The check-in success screen. It used to be a bare headline and a balance line
# while the purchase success screen next to it showed a receipt — same moment,
# two different-looking screens.
class CheckinSuccessTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "chk")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, gamification_enabled: true)
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Thảo Điền", active: true)
      @ws.missions.create!(title: "Điểm danh", icon: "📍", mission_type: "checkin",
                           period: "daily", goal: 1, reward_points: 20, position: 0, active: true)
    end
    post "/w/#{@ws.slug}/login", params: { email: "chk@example.com" }
    post "/w/#{@ws.slug}/verify",
         params: { code: ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code } }
  end

  test "checking in shows the receipt: branch, what it was, and the new balance" do
    token = ActsAsTenant.with_tenant(@ws) { Checkin.encode(@ws, @outlet) }
    get "/w/#{@ws.slug}/scan/resolve", params: { checkin: token }
    assert_response :success
    assert_match @outlet.name, response.body, "the branch checked in at should be named"
    assert_match I18n.t("customer.checkin.daily"), response.body
    assert_match I18n.t("customer.earn_success.new_balance"), response.body
  end
end
