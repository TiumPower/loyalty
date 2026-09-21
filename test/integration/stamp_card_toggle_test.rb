require "test_helper"

# Pause / run a stamp card from the list. It replaced a checkbox that only took
# effect when the whole card was saved, so the click must persist on its own.
class StampCardToggleTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "stamptoggle", status: "trial")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @card = StampCard.create!(workspace: @ws, title: "Mua 9 tặng 1", target_count: 9, active: true)
    end
    sign_in @user
  end

  test "the toggle flips the card and answers JSON for the inline button" do
    patch "/merchant/stamp_cards/#{@card.id}/toggle", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_equal false, body["active"]
    assert_not @card.reload.active?

    patch "/merchant/stamp_cards/#{@card.id}/toggle", as: :json
    assert JSON.parse(response.body)["active"]
    assert @card.reload.active?
  end

  test "without JS the toggle still works and comes back with a notice" do
    patch "/merchant/stamp_cards/#{@card.id}/toggle"
    assert_redirected_to merchant_gamification_path
    assert_equal I18n.t("merchant.gami.stamp_suspended", title: @card.title), flash[:notice]
    assert_not @card.reload.active?
  end

  test "the page renders the pause button instead of the active checkbox" do
    get "/merchant/gamification"
    assert_response :success
    assert_match I18n.t("merchant.gami.stamp_pause"), response.body
    assert_match toggle_merchant_stamp_card_path(@card), response.body
    # The "new card" form still posts active=true as a hidden field; what must
    # be gone is the checkbox on a saved card.
    assert_no_match(/type="checkbox"[^>]*name="stamp_card\[active\]"/, response.body)
  end

  # Staff without manage rights must not be able to pause a card.
  test "a counter-staff member cannot toggle" do
    staff = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: staff, workspace: @ws, role: "staff") }
    sign_in staff
    patch "/merchant/stamp_cards/#{@card.id}/toggle", as: :json
    assert_response :redirect
    assert @card.reload.active?
  end

  # Missions got the same treatment as stamp cards.
  test "a mission toggles inline too" do
    mission = ActsAsTenant.with_tenant(@ws) do
      Mission.create!(workspace: @ws, title: "Check-in mỗi ngày", mission_type: "checkin",
                      period: "daily", reward_points: 20, goal: 1, active: true)
    end
    patch "/merchant/missions/#{mission.id}/toggle", as: :json
    assert_response :success
    assert_equal false, JSON.parse(response.body)["active"]
    assert_not mission.reload.active?

    get "/merchant/gamification"
    assert_match toggle_merchant_mission_path(mission), response.body
    assert_no_match(/type="checkbox"[^>]*name="mission\[active\]"/, response.body)
  end
end
