require "test_helper"

# Merchants could not tell where the "Thưởng: …" list came from, so the stamp /
# badge editors spell it out and link to the rewards page.
class GamificationRewardGuideTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "gamiguide", status: "trial")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  def create_reward(title, stock: nil, redeemed: 0)
    ActsAsTenant.with_tenant(@ws) do
      Reward.create!(workspace: @ws, title: title, kind: "gift", value_unit: "item",
                     active: true, stock: stock, redeemed_count: redeemed)
    end
  end

  test "with no rewards yet the guide points at creating one" do
    get "/merchant/gamification"
    assert_response :success
    assert_match I18n.t("merchant.gami.reward_source_empty"), response.body
    assert_match I18n.t("merchant.gami.reward_source_create"), response.body
    assert_match merchant_rewards_path, response.body
  end

  test "with rewards the guide explains the picker for stamps and badges" do
    create_reward("Cà phê")
    get "/merchant/gamification"
    assert_response :success
    assert_match I18n.t("merchant.gami.reward_source_stamp"), response.body
    assert_match I18n.t("merchant.gami.reward_source_badge"), response.body
    assert_match I18n.t("merchant.gami.reward_source_manage"), response.body
    assert_match I18n.t("merchant.gami.reward_opt", title: "Cà phê"), response.body
  end

  # A sold-out prize pays out nothing when a card fills up, so it is not offered.
  test "a sold-out reward is not offered in the picker" do
    sold_out = create_reward("Hết suất", stock: 2, redeemed: 2)
    ok = create_reward("Còn suất", stock: 2, redeemed: 0)
    get "/merchant/gamification"
    assert_response :success
    assert_match(/value="#{ok.id}"/, response.body)
    assert_no_match(/value="#{sold_out.id}"/, response.body)
  end

  # ...but a card already pointing at it keeps it, flagged, so saving that card
  # does not silently drop its reward.
  test "a reward already attached stays in the picker, flagged as sold out" do
    reward = create_reward("Sắp hết", stock: 1)
    ActsAsTenant.with_tenant(@ws) do
      StampCard.create!(workspace: @ws, title: "Mua 2 tặng 1", target_count: 2, reward: reward, active: true)
      reward.update_columns(redeemed_count: 1) # sells out afterwards
    end
    get "/merchant/gamification"
    assert_response :success
    assert_match(/value="#{reward.id}"/, response.body)
    assert_match I18n.t("merchant.gami.reward_opt", title: "Sắp hết") +
                 I18n.t("merchant.campaigns.reward_opt_sold_out"), response.body
  end
end
